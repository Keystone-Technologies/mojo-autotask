package Mojo::Autotask;
use Mojo::Base -base;

use Mojo::Autotask::ExecuteCommand;
use Mojo::Autotask::Query;
use Mojo::Autotask::Util 'localtime';
use Mojo::Collection;
use Mojo::JSON;
use Mojo::Promise;
use Mojo::Redis;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util 'dumper';

use Carp;
use Time::Seconds;
use SOAP::Lite;#  +trace => 'debug';
use XML::LibXML;
use Scalar::Util qw(blessed);
use MIME::Base64;
use Encode;

use constant DEBUG   => $ENV{MOJO_AUTOTASK_DEBUG}   || 0;
use constant REFRESH => $ENV{MOJO_AUTOTASK_REFRESH} || 0;

use vars qw($VERSION);
$VERSION = '1.60';

my @VALID_OPS = qw(
  Equals NotEqual GreaterThan LessThan GreaterThanOrEquals LessThanOrEquals
  BeginsWith EndsWith Contains IsNull IsNotNull IsThisDay Like NotLike
  SoundsLike
);

my @VALID_CONDITIONS = qw(AND OR);

has collection  => sub {
  Mojo::Collection->with_roles(qw/+Autotask +Hashes +UtilsBy/)->new
};
has ec          => sub { Mojo::Autotask::ExecuteCommand->new };
has entities    => sub { {} };
has init        => sub { $ENV{MOJO_AUTOTASK_INIT} // 1 };
has password    => sub { $ENV{AUTOTASK_PASSWORD} or die };
has redis       => sub { state $r = Mojo::Redis->new };
has soap_proxy  => sub { Mojo::URL->new('https://webservices.autotask.net/atservices/1.6/atws.asmx') };
has tracking_id => sub { $ENV{AUTOTASK_TRACKINGID} or die };
has ua          => sub { Mojo::UserAgent->new };#->with_roles('+Queued') };
has username    => sub { $ENV{AUTOTASK_USERNAME} or die };
has ws_url      => sub { Mojo::URL->new('http://autotask.net/ATWS/v1_6/') };

has _query      => sub { Mojo::Autotask::Query->new };#(at => shift) };

has _api_records_per_create => 200;
has _api_records_per_delete => 200;
has _api_records_per_query  => 500;
has _api_records_per_update => 200;

###

sub create { shift->_write(create => shift) }

sub create_p { shift->_write_p(create => shift) }

# HIGH
sub create_attachment_p {}

# HIGH: Test this, this is just copied from create()
#       Need to read the API
# BTW:  Need to test SOAP functions just like WebService::Autotask
sub delete { shift->_write(delete => shift) }

sub delete_p { shift->_write_p(delete => shift) }

# HIGH
sub delete_attachment_p {}

# HIGH
sub get_attachment_p {}

sub get_entity_info {
  shift->get_entity_info_p(@_)->with_roles('+Get')->get;
}

sub get_entity_info_p {
  my $self = shift;
  $self->_memoize_p(_post_p => GetEntityInfo => undef => ONE_DAY * 30)->then(sub {
    ref $_[0] eq 'HASH' ? shift->{EntityInfo} : {};
  });
}

sub get_field_info {
  shift->get_field_info_p(@_)->with_roles('+Get')->get;
}

sub get_field_info_p {
  my ($self, $entity) = @_;
  my $data = SOAP::Data->name('psObjectType')->value($entity);
  $self->_memoize_p(_post_p => GetFieldInfo => $data => ONE_DAY)->then(sub {
    ref $_[0] eq 'HASH' ? shift->{Field} : {};
  });
}

#Where Value == 8, return Label
#Where Label eq Partner, return Value
sub get_picklist_options {
  my ($self, $entity, $field, $kv, $vk) = @_;
  die unless $entity && $field;
  #$self->load_field_and_udf_info($entity); # Is this necessary? Really slows everything down
  my $picklist = $self->entities->{$entity}->{fields}->{$field}->{PicklistValues}->{PickListValue};
  return unless $picklist;
  return $picklist unless $kv;
  my $_kv = $kv eq 'Value' ? 'Label' : 'Value';
  $picklist = {map { $_->{$kv} => $_ } @$picklist};
  return $picklist unless defined $vk;
  return $picklist->{$vk}->{$_kv};
}

sub get_threshold_and_usage_info {
  shift->get_threshold_and_usage_info_p(@_)->with_roles('+Get')->get;
}

sub get_threshold_and_usage_info_p {
  my $self = shift;
  $self->_memoize_p(_post_p => getThresholdAndUsageInfo => undef => 3)->then(sub {
    shift->{EntityReturnInfoResults}->{EntityReturnInfo}
  });
}

sub get_udf_info {
  shift->get_udf_info_p(@_)->with_roles('+Get')->get;
}

sub get_udf_info_p {
  my ($self, $entity) = @_;
  my $data = SOAP::Data->name('psTable')->value($entity);
  $self->_memoize_p(_post_p => getUDFInfo => $data => ONE_DAY)->then(sub {
    ref $_[0] eq 'HASH' ? shift->{Field} : {};
  });
}

sub get_zone_info {
  shift->get_zone_info_p(@_)->with_roles('+Get')->get;
}

sub get_zone_info_p {
  my $self = shift;
  my $data = SOAP::Data->name('UserName')->value($self->username);
  $self->_memoize_p(_post_p => getZoneInfo => $data => ONE_DAY * 30)->then(sub {
    shift
  });
}

sub load_entity_info {
  shift->load_entity_info_p(@_)->wait;
}

sub load_entity_info_p {
  my $self = shift;
  return Mojo::Promise->resolve unless $self->init || !keys %{$self->entities};
  $self->init(0);
  $self->get_entity_info_p->then(sub {
    foreach ( ref $_[0] eq 'ARRAY' ? @{$_[0]} : () ) {
      my $backup_fields = $self->_backup_fields($_->{Name});
      $_->{fields} = $backup_fields if $backup_fields;
      $self->entities->{$_->{Name}} = $_;
    }
    die "Unable to get a list of valid Entities from the Autotask server"
      unless keys %{$self->entities};
  });
}

sub load_field_and_udf_info {
  shift->load_field_and_udf_info_p(@_)->with_roles('+Get')->get;
}

sub load_field_and_udf_info_p {
  my $self = shift;
  my @p = ();
  foreach my $entity ( sort @_ ) {
    next unless $self->init || !exists $self->entities->{$entity}->{fields};
    warn "-- get_info $entity" if DEBUG > 1;
    push @p, $self->get_field_info_p($entity)->then(sub {
      my $res = shift;
      warn "-- get_field_info $entity" if DEBUG;
      $res = [] unless ref $res eq 'ARRAY';
      $self->entities->{$entity}->{fields}->{$_->{Name}} = $_ for @$res;
      return $_[0];
    });
    push @p, $self->get_udf_info_p($entity)->then(sub {
      my $res = shift;
      warn "-- get_udf_info $entity" if DEBUG;
      $res = [] unless ref $res eq 'ARRAY';
      $res = [map { $_->{IsUDF} = 'true'; $_ } @$res];
      $self->entities->{$entity}->{fields}->{$_->{Name}} = $_ for @$res;
      return $_[0];
    });
  }
  $self->init(0);
  @p ? Mojo::Promise->all(@p) : Mojo::Promise->resolve;
}

sub new {
  my $self = shift->SUPER::new(@_);

  my $userinfo = join ':', $self->username, $self->password;
  # LOW: Resolve recursively like WebService::Autotask?
  my $zone_info = $self->get_zone_info;
  $self->soap_proxy(Mojo::URL->new($zone_info->{URL})
                             ->userinfo($userinfo));
  $self->ec->zone(Mojo::URL->new($zone_info->{WebUrl}));

  warn $self->soap_proxy->to_unsafe_string if DEBUG;

  # LOW: implement a notifier system
  # The idea is that when one process updates the cached data, any other
  # processes could be notified to re-update their in-memory data
  if ( $self->redis ) {
    $self->redis->pubsub->listen('schema:update:entity' => sub {
      my ($pubsub) = @_;
      $self->init(1)->load_entity_info_p;
    });
    $self->redis->pubsub->listen('schema:update:field_and_udf' => sub {
      my ($pubsub, $entity) = @_;
      $self->init(1)->load_field_and_udf_info_p($entity);
    });
  }

  return $self->_init_schema;
}

sub query {
  shift->query_p(@_)->with_roles('+Get')->get;
}

sub query_p {
  my $self = shift;
  my $query = ref $_[0] eq 'Mojo::Autotask::Query'
            ? shift
            : $self->_query->new(ref $_[0] eq 'HASH' ? shift : ());
  $query->entity(shift) if $_[0] && !ref $_[0];
  $query->query(shift) if $_[0] && ref $_[0] eq 'ARRAY';

  # Validate that we have the right arguments.
  $self->_validate_entity_argument($query->entity, 'query');

  warn dumper(\@$query) if DEBUG > 1;
  my $query_xml = $self->_create_query_xml($query->entity, \@$query);
  my $data = SOAP::Data->name('sXML')->value($query_xml);
  my @soap = $self->_soap(query => $data);
  if ( $self->redis && defined $query->expire ) {
    warn "-- Caching _post_p query with Redis" if DEBUG > 1;
    # HIGH: I think we can go back to memoize_p
    my $res = $self->redis->cache->refresh(REFRESH)->compute_p(
      $query->key, $query->expire, sub { $self->_post_p(@soap) }
    )->then(sub {
      my $res = shift;
      if ($res->{Errors} || $res->{ReturnCode} ne '1') {
        die $res->{Errors}->{ATWSError};
      }
      $self->collection->new(_get_entity_results($res));
    })->catch(sub {
      warn "Something went wrong in query_p: $_[0]";
      $self->collection->new;
    })->with_roles('+Get')->get;
    # It's nice to support the persist feature, but it proly shouldn't be used
    # That will be a lot of data sitting around never getting touched
    # The expiration should be the end of the CreateDate range
    $self->redis->db->persist(join ':', $self->redis->cache->namespace, $query->key)
      unless $query->expire || $res->size < $self->_api_records_per_query;
    Mojo::Promise->resolve($res);
  } else {
    warn "-- Not Caching _post_p query with Redis" if DEBUG > 1;
    $self->_post_p(@soap)->then(sub {
      my $res = shift;
      if ($res->{Errors} || $res->{ReturnCode} ne '1') {
        die $res->{Errors}->{ATWSError};
      }
      $self->collection->new(_get_entity_results($res));
    })->catch(sub {
      warn "Something went wrong in query_p: $_[0]";
      $self->collection->new;
    });
  }
}

sub query_all {
  my $self = shift;
  my $query = ref $_[0] eq 'Mojo::Autotask::Query'
            ? shift
            : $self->_query->new(ref $_[0] eq 'HASH' ? shift : ());
  $query->entity(shift) if $_[0] && !ref $_[0];
  $query->query(shift) if $_[0] && ref $_[0] eq 'ARRAY';
 
  # Validate that we have the right arguments.
  $self->_validate_entity_argument($query->entity, 'query');
 
  my $data = $query->data || {};
  while ( 1 ) {
    my $md5_sum = $query->_md5_sum;
    my $res = $self->query($query);
    last unless @$res;
    $query->last_id($res->[-1]->{id});
    $_->{_batch} = $query->key for @$res;
    $data = {%$data, map { $_->{id} => $_ } @$res};
    warn sprintf "-- %s records, batch %s (last id %s, create_date %s), %s total",
                 $res->size, $md5_sum, $query->last_id, $res->last->{CreateDate}||'',
                 scalar keys %$data if DEBUG;
    last if @$res < $self->_api_records_per_query;
  }
  $data = $self->collection->new(values %$data);
  return $data;
  # HIGH:
  # This may add some new records, but it may also be an update for a previously cached record
  if ( my $field = $query->refresh_field && !$query->data ) {
    $query->last_activity($data->sort(sub{$a->{$field} <=> $b->{$field}})->last->{$field});
    $query->data({map { $_->{id} => $_ } @$data});
    my $updates = $self->query_all($query);
    if ( $updates->size ) {
      # Need to update the redis keys with these updates
      $data = $updates;
    }
  }
  return $data;
}

sub query_all_p { Mojo::Promise->resolve(shift->query_all(@_)) }

sub update { shift->_write(update => shift) }

sub update_p { shift->_write_p(update => shift) }

###

sub _backup_fields {
  my ($self, $entity) = @_;
  return unless $self->entities->{$entity};
  return unless $self->entities->{$entity}->{fields};
  $self->entities->{$entity}->{fields};
}

sub _init_schema {
  my $self = shift;
  my $init = $self->init;
  $self->init(1)->load_entity_info;
  $self->init(1)->load_field_and_udf_info(keys %{$self->entities}) if $init;
  return $self;
}

sub _memoize_p {
  my ($self, $method, $action, $data, $expire) = @_;
  my @data = ref $data eq 'ARRAY' ? @$data : $data;
  my @soap = $self->_soap($action => @data);
  my $redis = $self->redis;
  if ( $redis && defined $expire ) {
    warn "-- Caching $method $action with Redis" if DEBUG > 1;
    my $res = $redis->cache->refresh(REFRESH)->memoize_p(
      $self, $method => [@soap], $expire
    )->catch(sub {
      warn "Something went wrong in _memoize_p: $_[0]";
    })->with_roles('+Get')->get;
    Mojo::Promise->resolve($res);
  } else {
    warn "-- Not Caching $method $action with Redis" if DEBUG > 1;
    $self->$method(@soap);
  }
}

# MED: Use minion to keep these queries refreshed
sub _post_p {
  my ($self, $action) = (shift, shift);
  warn dumper(\@_) if DEBUG > 1;
  $self->ua->post_p(@_)->then(sub {
    warn "-- Refresh $action (sending SOAP request)" if DEBUG > 1;
    #Mojo::File::tempfile(UNLINK => 0)->spurt($_[0]->result->dom);
    SOAP::Deserializer->deserialize(shift->result->dom)->result
  });
}

sub _soap {
  my ($self, $action) = (shift, shift);
  warn "-- Building SOAP for $action (not yet sending SOAP request)"
    if DEBUG > 1;
  my @soap = (
    $action,
    $self->soap_proxy->to_unsafe_string,
    {
      'Accept'       => ['text/xml', 'multipart/*', 'application/soap'],
      'Content-Type' => 'text/xml; charset=utf-8',
      'SOAPAction'   => $self->ws_url->clone->path($action)->to_string
    },
    SOAP::Serializer->default_ns($self->ws_url->to_string)->envelope(
      method => $action => @_,
      SOAP::Header->attr({xmlns => $self->ws_url->to_string})
                  ->value(\SOAP::Data->value($self->tracking_id)
                                     ->name('IntegrationCode'))
                  ->name('AutotaskIntegrations'),
    )
  );
  warn dumper(\@soap) if DEBUG > 2;
  return @soap;
}

sub _write {
  my ($self, $type, $collection) = @_;

  die "Missing type argument in call to _write (create, delete, update)"
    unless $type && $type =~ /^(create|delete|update)$/;
  die "Missing collection argument in call to _write"
    unless $collection;
  die "Collection argument not of type Mojo::Collection"
    unless $collection->isa('Mojo::Collection');

  my $api_records_per = "_api_records_per_$type";

  my $done  = $collection->new;
  my $batch = Mojo::Collection->new;
  my $todo  = Mojo::Collection->new;

  # Validate that we have the right arguments.
  $collection->each(sub {
    $self->_validate_entity_argument($_, $type);

    # Verify all fields provided are valid.
    $self->_validate_fields($_);

    # Autotask API limits how many updates can occur per update
    # Create batches and push each full batch to the todo collection
    push @$batch, _entity_as_soap_data($_);
    if ( $batch->size == $self->$api_records_per ) {
      push @$todo, $batch;
      $batch = $batch->new;
    }
  });
  # Keep the final, unfilled batch
  push @$todo, $batch if $batch->size;

  $todo->each(sub {
    my $data = SOAP::Data->name('Entities')
                         ->value(\SOAP::Data->name('array' => @$_));
    push @$done, {$type => $data};
    #$self->_post_p($type => $data)->then(sub {
    #  push @$done, _get_entity_results(shift);
    #})->wait;
  });

  return $done;
}

sub _write_p { Mojo::Promise->resolve(shift->_write(@_)) }

###
# These 9 functions are from WebService::Autotask
###

# LOW: Mojo::DOM should be able to do this
# query() uses this
sub _create_query_xml {
  my ($self, $entity, $query) = @_;

  my $doc = XML::LibXML::Document->new();
  my $xml = $doc->createElement('queryxml');
  $doc->setDocumentElement($xml);

  my $elem = $doc->createElement('entity');
  $elem->appendChild($doc->createTextNode($entity));
  $xml->appendChild($elem);
  my $q_elem = $doc->createElement('query');

  # Figure out the query values.
  foreach my $item (@$query) {
    # Is this a field or a condition?
    if (exists($item->{name})) {
      # We have a field.
      $q_elem->appendChild($self->_parse_field($entity, $doc, $item));
    }
    elsif (exists($item->{elements})) {
      # We have a condition.
      $q_elem->appendChild($self->_parse_condition($entity, $doc, $item));
    }
    else {
      # We have an invalid element.
      die "Found an invalid element in query element";
    }
  }

  $xml->appendChild($q_elem);
  return $xml->toString();
}

# update() and create() use this
sub _entity_as_soap_data {
  my ($entity) = @_;

  my @fields = ();

  foreach my $f_name (sort(keys(%$entity))) {
    my $field;
    if ($f_name eq 'UserDefinedFields') {
      # BUG: LOW: next is needed here to avoid an unsolved bug
      next;
      $field = _udf_as_soap_data($entity->{$f_name});
    } else {
      # Assume non-ASCII is UTF-8
      my $data = decode("utf8", $entity->{$f_name});
      $field = SOAP::Data->name($f_name => $data);
      # SOAP::Lite will treat as binary if UTF-8
      $field->type("string") if ($data ne $entity->{$f_name});
    }
    push @fields, $field;
  }

  return SOAP::Data->name(
    Entity => \SOAP::Data->value(@fields))->attr({'xsi:type' => ref($entity)}
  );
}

# This function is used to return a consistent value: a list, not a ref
# query(), update(), and create() use this
sub _get_entity_results {
  my ($result) = @_;

  # Make sure we have results to return.
  if (!exists($result->{EntityResults}) ||
      ref($result->{EntityResults}) ne 'HASH' ||
      !exists($result->{EntityResults}->{Entity})) {
    return ();
  }

  my $ents = $result->{EntityResults}->{Entity};

  # Return the actual array instead of an array ref if we got one.
  if (ref($ents) eq 'ARRAY') {
    return (@$ents);
  }

  # Return the item to be assigned as an array.
  return($ents);
}

# _create_query_xml() uses this; and it's recursive
sub _parse_condition {
  my ($self, $entity, $doc, $condition) = @_;

  my $c_elem = $doc->createElement('condition');
  if ($condition->{operator}) {
    die $condition->{operator} . " is not a valid operator for a condition"
      if (!grep {$_ eq $condition->{operator}} @VALID_CONDITIONS);
    $c_elem->setAttribute('operator', $condition->{operator});
  }

  # Now add each element found in the condition.
  foreach my $item (@{$condition->{elements}}) {
    # Is this a field or a condition?
    if (exists($item->{name})) {
      # We have a field.
      $c_elem->appendChild($self->_parse_field($entity, $doc, $item));
    }
    elsif (exists($item->{elements})) {
      # We have a condition.
      $c_elem->appendChild($self->_parse_condition($entity, $doc, $item));
    }
    else {
      # We have an invalid element.
      die "Found an invalid element in query element";
    }
  }

  return $c_elem;
}

# _create_query_xml() and _parse_condition() uses this
sub _parse_field {
  my ($self, $entity, $doc, $field) = @_;

  # Check to see that this entity actually has a field with this name.
  die "Invalid query field " . $field->{name} . " for entity $entity"
    if (!$self->entities->{$entity}->{fields}->{$field->{name}}->{IsQueryable});
  my $f_elem = $doc->createElement('field');
  if ($self->entities->{$entity}->{fields}->{$field->{name}}->{IsUDF}) {
    $f_elem->setAttribute('udf', 'true');
  }
  $f_elem->appendChild($doc->createTextNode($field->{name}));

  # Go through the expressions.
  foreach my $item (@{$field->{expressions}}) {
    die "Invalid op " . $item->{op} . " in expression"
      if (!grep {$_ eq $item->{op}} @VALID_OPS);
    my $exp = $doc->createElement('expression');
    $exp->setAttribute('op', $item->{op});
    $exp->appendChild($doc->createTextNode($item->{value}));
    $f_elem->appendChild($exp);
  }

  return $f_elem;
}

# LOW: Change this to be more Mojo-like
# query(), update(), create(), and delete_attachment() use this
sub _set_error {
  my ($self, $errs) = @_;

  $self->{error} = '';

  if (ref($errs) eq 'HASH') {
    $errs = [ $errs ];
  }

  if (ref($errs) eq 'ARRAY') {
    foreach my $err (@$errs) {
      $self->{error} .= "ATWSError: " . $err->{Message} . "\n";
    }
  }

  if (!$self->{error}) {
    $self->{error} = "An unspecified error occured. This usually is due to bad SOAP formating based on the data passed into this method";
  }

  $self->{error} =~ s/\n$//;
}

# _entity_as_soap_data() uses this
sub _udf_as_soap_data {
  my ($udfs) = @_;

  my @fields = ();

  foreach my $field (@{$udfs->{UserDefinedField}}) {
    # Assume non-ASCII is UTF-8
    my $data = decode("utf8", $field);
    my $val = SOAP::Data->value($data);
    # SOAP::Lite will treat as binary if UTF-8
    $val->type("string") if ($data ne $field);
    push(@fields, SOAP::Data->name(UserDefinedField => $val));
  }

  return SOAP::Data->name(UserDefinedFields => \SOAP::Data->value(@fields));
}

# query(), update(), and create() use this
sub _validate_entity_argument {
  my ($self, $entity, $type) = @_;

  my $flag;
  if ($type eq 'query') {
    $flag = 'CanQuery';
  }
  elsif ($type eq 'create') {
    $flag = 'CanCreate';
  }
  elsif ($type eq 'update') {
    $flag = 'CanUpdate';
  }

  my $e_type = blessed($entity);
  if (!$e_type) {
    if (ref($entity) eq '') {
      # Our entity is actually a type string.
      $e_type = $entity;
    }
    else {
      die "Entity has not been blessed";
    }
  }

  # Are we allowed to query this entity?
  if (!$e_type) {
    die "Missing entity argument in call to $type"
  }
  elsif ( not exists $self->entities->{$e_type} ) {
    die "$e_type is not a valid entity. Valid entities are: " .
        join(', ', keys %{$self->entities})
  }
  elsif ($self->entities->{$e_type}->{$flag} eq 'false') {
    die "Not allowed to $type $e_type"
  }

  $self->load_field_and_udf_info($entity);

  return 1;
}

# update() and create() use this
sub _validate_fields {
  my ($self, $ent) = @_;

  my $type = blessed($ent);
  my $e_info = $self->entities->{$type};

  foreach my $f_name (keys %$ent) {
    if ($f_name eq 'UserDefinedFields') {
      # Special case field. Look at the actual user defined fields.
      # BUG: LOW: next is needed here to avoid an unsolved bug
      next;
      foreach my $udf (@{$ent->{$f_name}->{UserDefinedField}}) {
        die "Field " . $udf->{Name} . " is not a valid $type entity user defined field"
          if (!$e_info->{fields}->{$udf->{Name}});
      }
    }
    else {
      die "Field $f_name is not a valid field for $type entity"
        if (!$e_info->{fields}->{$f_name});
    }
  }

  return 1;
}

1;

=encoding utf8

=head1 NAME

Mojo::Autotask - Interface to the Autotask WebServices SOAP API 1.6 and
ExecuteCommand URL builder.

=head1 SYNOPSIS

  my $at = Mojo::Autotask->new(
    username => 'user@autotask.account.com',
    password => 'some_password',
    tracking_id => 'JJLKJE2983LJOL2KLJ',
  );

  my $collection = $at->query(Account => [
    {
      name => 'AccountName',
      expressions => [{op => 'BeginsWith', value => 'b'}]
    },
  ]);

  $collection->first->{AccountName} = 'New Account Name';

  $at->update(@$list);

  $list = $at->create(
    bless({
      AccountName => "Testing Account Name",
      Phone => "800-555-1234",
      AccountType => 1,
      OwnerResourceID => 123456,
    }, 'Account')
  );

=head1 DESCRIPTION

L<Mojo::Autotask> is a module that provides an interface to the Autotask
WebServices SOAP API 1.6 and ExecuteCommand URL builder. Using this method and
your Autotask login credentials you can access and manage your Autotask items
using this interface. You should read the Autotask L<WebServices SOAP-based API
documentation|https://ww5.autotask.net/help/Content/LinkedDOCUMENTS/WSAPI/T_WebServicesAPIv1_6.pdf>
and L<ExecuteCommand URL builder documentation|https://ww5.autotask.net/help/Content/LinkedDOCUMENTS/PDFBatchOutput/ExecuteCommandAPI.pdf>
prior to using this module.

Note: all input is assumed to be UTF-8.

=head1 ATTRIBUTES

L<Mojo::Autotask> implements the following attributes.

=head2 cache

  my $cache = $at->cache;
  $at       = $at->cache(Mojo::Recache->new);

L<Mojo::Recache> object used to cache slow queries from Autotask.

=head2 cached

  my $bool = $at->cached;
  $at      = $at->cached(1);

L<Mojo::Recache> will set this to true so that methods of this package can know
that they are being cached and perhaps behave differently. This is useful for
doing cache updates of large volumes of data as opposed to doing complete
refreshes each time.

=head2 collection

  my $collection = $at->collection;
  $at            = $at->collection(Mojo::Collection->new);

The default L<Mojo::Collection> object to use for storing data.

=head2 ec

  my $ec = $at->ec;
  $at    = $at->ec(Mojo::Autotask::ExecuteCommand->new);

L<Mojo::Autotask::ExecuteCommand> object used to build Autotask ExecuteCommand
URLs.

=head2 entity_info

  my $collection = $at->entity_info;
  $at            = $at->entity_info(Mojo::Collection);

A L<Mojo::Collection> of entity info.

=head2 field_info

  my $hash = $at->field_info;
  $at      = $at->field_info({});

A hash ref of L<Mojo::Collection> objects of entity field info.

=head2 limits

  my $limits = $at->limites;
  $at        = $at->limits(Mojo::Autotask::Limits->new);

L<Mojo::Autotask::Limits> object used for refining the query filter.

=head2 max_memory

  my $max_memory = $at->max_memory;
  $at            = $at->max_memory(500_000);

L<Mojo::Autotask> can consume a lot of memory with the amount of data that might
be pulled through the API. L</"max_memory"> limits the amount of data retrieved
by limiting the amount of memory used by the perl process. Defaults to 250,000
bytes.

=head2 max_records

  my $max_records = $at->max_records;
  $at             = $at->max_records(5_000);

Autotask WebServices API returns a maximum of 500 records per fetch;
L<Mojo::Autotask> automatically continues to make additional fetches, capturing
an additional 500 records per fetch, for a maximum collection of
L</"max_records"> records. Defaults to 2,500.

=head2 new

  my $at = Mojo::Autotask->new;

Create a new instance and initialize by determining the appropriate zone for the
supplied L</"username">.

=head2 password

  my $password = $at->password;
  $at          = $at->password('secret');

Autotask WebServices API password. This attribute is required and has no
default value. Defaults to $ENV{AUTOTASK_PASSWORD} if set.

=head2 soap_proxy

  my $soap_proxy = $at->soap_proxy;
  $at            = $at->soap_proxy(Mojo::URL->new);

The L<Mojo::URL> object for the Autotask WebServices API SOAP Proxy URL.
Defaults to https://webservices.autotask.net/atservices/1.6/atws.asmx.

If you know which proxy server you are to use then you may supply it here. By
default one of the proxies is used and then the correct proxy is determined
after logging in. If the default proxy is not correct the correct proxy will
then be logged into automatically. This option should not be required.

=head2 threshold_and_usage_info

  my $tui = $at->threshold_and_usage_info;
  $at     = $at->threshold_and_usage_info({})

XXXXXXXXXXX

=head2 udf_info

  my $udf_info = $at->udf_info;
  $at          = $at->udf_info({})

A hash ref of L<Mojo::Collection> objects of entity field UDF info.

=head2 tracking_id

  my $tracking_id = $at->tracking_id;
  $at             = $at->tracking_id('AKJHADLK7658KJH78');

Autotask WebServices API tracking id. This attribute is required and has no
default value. Defaults to $ENV{AUTOTASK_TRACKINGID} if set.

The tracking id is a new attribute required with version 1.6 of the Web
Services API.

=head2 username

  my $username = $at->username;
  $at          = $at->username('user@abc.xyz');

Autotask WebServices API username. This attribute is required and has no
default value. Defaults to $ENV{AUTOTASK_USERNAME} if set.

It is recommended to create a new API-only Autotask account for each
application. This limits the effect of password breaches as well as enables
auditing within Autotask to know which application took what action.

=head2 ws_url

  my $ws_url = $at->ws_url;
  $at        = $at->us_url(Mojo::URL->new);

The L<Mojo::URL> object for the Autotask WebServices API SOAP URL.
Defaults to http://autotask.net/ATWS/v1_6/.

=head2 zone_info

  my $zi = $at->zone_info;
  $at    = $at->zone_info({});

XXXXXXXX

=head1 METHODS

=head2 clone

  my $at = $at->clone;

Clone the autotask object instance, attributes passed to clone overwrite any
attributes set in the original instance.

=head2 create

  my $created = $at->create($collection)

Create the given entities. Entites will be verified prior to submitted to
verify that they can be created, any fields that are not createable will
be ignored on creation. Each object reference needs to be blessed with the
entity type that it is (Account, Contact, etc). Returns a L</"collection"> of
entites that were created successfully. See the section on Entity format for
more details on how to format entities to be accepted by this method.

The Autotask API imposes a limit on the number of records per request, and this
method accounts for that and batches the collection into multiple requests.

=head2 create_attachment($attach)

Create a new attachment. Takes a hashref containing Data (the raw data of
the attachment) and Info, which contains the AttachmentInfo. Returns the
new attachment ID on success.

=head2 delete

  my $deleted = $at->delete($collection)
  my $deleted = $at->delete($at->query('Account')->grep(sub{
                  $_->{AccountName} =~ /^B/)
                }))

Delete the given entities. Entites will be verified prior to submitted to
verify that they can be deleted, any fields that are not deleteable will
be ignored on deletion. Each object reference needs to be blessed with the
entity type that it is (Account, Contact, etc). Returns a L</"collection"> of
entites that were deleted successfully. See the section on Entity format for
more details on how to format entities to be accepted by this method.

The Autotask API imposes a limit on the number of records per request, and this
method accounts for that and batches the collection into multiple requests.

=head2 delete_attachment($id)

Delete an attachment; the only argument is the attachment ID. Returns true on
success or sets the error string on failure.

=head2 get_attachment($id)

Fetch an attachment; the only argument is the attachment ID. Returns a
hashref of attachment Data and Info, or undef if the specified attachment
doesn't exist or if there is an error.

=head2 get_entity_info

  my $entities = $at->get_entity_info;
  my $entity   = $at->get_entity_info($entity);

Return entity into.

=head2 get_field_info

  my $fields = $at->get_field_info($entity)
  my $field  = $at->get_field_info($entity, $field)

Return field info for a specified entity.

=head2 get_picklist_options

  my $collection = $at->get_picklist_options($entity, $field)
  my $collection = $at->get_picklist_options($entity, $field, $key)
  my $collection = $at->get_picklist_options($entity, $field, $key, $value)

Return a L<Mojo::Collection> that contains the ID values and options for a
picklist field item. If the field is not a picklist field then an empty hash
will be retruned. The hash is formated with the labels as keys and the values
as the values.

=head2 get_threshold_and_usage_info

  my $collection = $at->get_field_info($entity)
  my $collection = $at->get_field_info($entity, $field)

XXXXXXXXXXX

=head2 get_udf_info

  my $udfs = $at->get_udf_info($entity)
  my $udf  = $at->get_udf_info($entity, $field)

Return UDF info for a specified entity.

=head2 get_zone_info

  my $collection = $at->get_field_info($entity)
  my $collection = $at->get_field_info($entity, $field)

XXXXXXXXXXXXX

=head2 query

  my $collection = $at->query($entity => [$query])
  my $collection = $at->query({$entity => $months} => [$query])
  my $collection = $at->query({Ticket => 12})

Generic query method to query the Autotask system for entity data. If an error
occurs while trying to parse the given arguments or creating the associated
QueryXML query this method will die with an appropriate error. Returns a
L</"collection"> of entity-specific blessed hash references.

The Autotask API imposes a limit on the number of records per request, and this
method accounts for that and batches the collection into multiple requests.

The query argument is an array reference of fields and conditions that are used
to construct the query XML. See below for the definition of a field and a
condition. See also L<Mojo::Autotask::Limit> for tools to assist with crafting
the query argument.

=over 4

=item B<field>

A field is a hash reference that contains the following entries:

=over 4

=item B<name>

The name of the field to be querying.

=item B<udf>

Boolean value to indicate if this field is a user defined field or not. Only
one UDF field is allowed per query, by default if ommited this is set to
false.

=item B<expressions>

An array of hash references for the expressions to apply to this field. The
keys for this hash refernce are:

=over 4

=item B<op>

The operator to use. One of: Equals, NotEqual, GreaterThan, LessThan,
GreaterThanOrEquals, LessThanOrEquals, BeginsWith, EndsWith, Contains, IsNull,
IsNotNull, IsThisDay, Like, NotLike or SoundsLike. If not in this list an
error will be issued.

=item B<value>

The appropriate value to go with the given operator.

=back

=back

=item B<condition>

A condition block that allows you define a more complex query. Each condition
element is a hash reference with the following fields:

=over 4

=item B<operator>

The condition operator to be used. If no operator value is given AND is assumed.
Valid operators are: AND and OR.

=item B<elements>

Each condition contains a list of field and/or expression elements. These have
already been defined above.

=back

=back

An example of a valid query argument for an Account entity would be:

  [
    {
      name => 'AccountName',
      expressions => [{op => 'Equals', value => 'New Account'}]
    },
    {
      operator => 'OR',
      elements => [
        {
          name => 'FirstName',
          expressions => [
            {op => 'BeginsWith', value => 'A'},
            {op => 'EndsWith', value => 'S'}
          ]
        },
        {
          name => 'LastName',
          expressions => [
            {op => 'BeginsWith', value => 'A'},
            {op => 'EndsWith', value => 'S'}
          ]
        }
      ]
    }
  ]

This will find all accounts with the AccountName of New Account that also
have either a FirstName or a LastName that begins with an A and ends with an
S.

For reference with the Autotask API manual, this example produces the following
XML:

XXXXXXXXXX

=back

=head2 update

  my $updated = $at->update($collection)
  my $updated = $at->update($at->query('Account')->each(sub {
                  $_->{AccountName} = uc($_->{AccountName})
                }))

Update the given entities. Entites will be verified prior to submitted to
verify that they can be updated, any fields that are not updatable will
be ignored on update. Each object reference needs to be blessed with the entity
type that it is (Account, Contact, etc). Returns a L</"collection"> of entites
that were updated successfully. See the section on Entity format for more
details on how to format entities to be accepted by this method.

The Autotask API imposes a limit on the number of records per request, and this
method accounts for that and batches the collection into multiple requests.

=head1 ENTITY FORMAT

The follow section details how to format a variable that contains entity
informaiton. Entites are required for creating and updating items in the
Autotask database.

An entity is a blessed hash reference. It is bless with the name of the type
of entity that it is (Account, Contract, Contact, etc). They keys of the hash
are the field names found in the Autotask entity object. The values are the
corresponding values to be used.

A special key is used for all user defined fields (UserDefinedFields). This
entry contains a hash reference containing one key UserDefinedField. This is
in turn an array reference containing each user defined field. The user
defined field entry looks simliar to this:

  {
    UserDefinedField => [
      {
        Name => "UserDefinedField1",
        Value => "Value for Field"
      },
      {
        Name => "SecondUDF",
        Value => "Value for SecondUDF"
      }
    ]
  }

When used together the entire structure looks something simliar to this:

  bless({
    FieldName1 => "Value for FieldName1",
    Field2 => "Value for Field2",
    UserDefinedFields => {
      UserDefinedField => [
        {
          Name => "UserDefinedField1",
          Value => "Value for Field"
        },
        {
          Name => "SecondUDF",
          Value => "Value for SecondUDF"
        }
      ]
    }
  }, 'EntityName')

Obviously the above is just an example. You will need to look at the actual
fields that are allowed for each Autotask entity. The user defined fields also
will depend on how your instance of Autotask has been configured.

=head1 DEPENDENCIES

L<Mojolicious>, L<SOAP::Lite>, L<MIME::Base64>, L<Memory::Usage>, L<Devel::Size>

=head2 optional

L<Mojo::Recache>

=head1 AUTHOR

Original L<WebService::Autotask> by Derek Wueppelmann (derek@roaringpenguin.com)

Attachment, UTF-8 support added by Chris Adams (cmadams@hiwaay.net)

Refactored as L<Mojo::Autotask> by Stefan Adams (stefan@adams.fm)

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

Autotask (tm) is a trademark of Autotask.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-autotask>, L<Mojolicious::Guides>,
L<https://mojolicious.org>, L<Minion>, L<Mojo::Recache>.

=cut