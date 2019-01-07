package Mojo::Autotask;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Autotask::ExecuteCommand;
use Mojo::Autotask::Limits;
use Mojo::Collection;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Recache;
use Mojo::Server;
use Mojo::URL;
use Mojo::Util qw/camelize dumper/;
use Mojolicious::Commands;
use Mojolicious::Plugins;
use Mojolicious::Validator;

use Carp;
use Memory::Usage;
use Devel::Size qw(size total_size);
use Time::Piece;
use SOAP::Lite;#  +trace => 'debug';
use XML::LibXML;
use Scalar::Util qw(blessed);
use MIME::Base64;
use Encode;

use vars qw($VERSION);
$VERSION = '0.01';

my @VALID_OPS = qw(
  Equals NotEqual GreaterThan LessThan GreaterThanOrEquals LessThanOrEquals 
  BeginsWith EndsWith Contains IsNull IsNotNull IsThisDay Like NotLike 
  SoundsLike
);

my @VALID_CONDITIONS = qw(AND OR);

#has app => sub { shift }, weak => 1;
has cache => sub { Mojo::Recache->new(app => shift) };
has collection => sub {
  Mojo::Collection->with_roles('+UtilsBy', '+Hashes', 'Mojo::Autotask::WebService::Role::Query')->new;
};
has ec => sub { Mojo::Autotask::ExecuteCommand->new };
has max_records => 2_500;
has max_memory => 250_000;
has limits => sub { Mojo::Autotask::Limits->new };
has log => sub { Mojo::Log->new };
has username => sub { die "No username provided" };
has password => sub { die "No password provided" };
has soap_proxy => sub { Mojo::URL->new('https://webservices.autotask.net/atservices/1.5/atws.asmx') };
has ws_url => sub { Mojo::URL->new('http://autotask.net/ATWS/v1_5/') };
has ws_ref => sub { Mojo::URL->new('https://www.autotask.net/help/Content/AdminSetup/2ExtensionsIntegrations/APIs/ExecuteCommand/UsingExecuteCommandAPI.htm') };

has valid_entities => sub { {} };
has picklist_values => sub { {} };

has _api_records_per_query => 500;

# $at->as_collection(sub { $_->cache->query(@_) });
# $at->as_collection($self->cache->query(@_));
# $at->as_collection(@{$self->cache->query(@_)});
sub as_collection {
  my ($self, $cb) = (shift, shift);
  return $self->collection->new(ref $cb eq 'CODE' ? map { @{$_->$cb} } $self : ref $cb eq 'ARRAY' ? @$cb : ($cb, @_));
}

sub create {
  my ($self, @entities) = @_;

  die "Missing entity argument in call to create" if (!@entities);

  # Validate that we have the right arguments.
  my @list;
  foreach my $ent (@entities) {
    $self->_validate_entity_argument($ent, 'create');

    # Get the entity information if we don't already have it.
    $self->_load_entity_field_info(blessed($ent));

    # Verify all fields provided are valid.
    $self->_validate_fields($ent);

    push(@list, _entity_as_soap_data($ent));
  }

  my $soap = $self->{_at_soap};
  my $res = $soap->create(SOAP::Data->name('Entities')->value(\SOAP::Data->name('array' => @list)))->result;

  if ($res->{Errors} || $res->{ReturnCode} ne '1') {
    # There were errors. Grab the errors and set $@ to their textual values.
    $self->_set_error($res->{Errors}->{ATWSError});
    return undef;
  }

  return _get_entity_results($res);
}

sub create_attachment {
  my ($self, $attach) = @_;

  # Get the entity information if we don't already have it.
  my $atb = "Attachment";
  my $ati = $atb . "Info";
  $self->_load_entity_field_info($ati);

  # Collect the Info fields
  my $e_info = $self->valid_entities->{$ati};
  my @inf;
  foreach my $f_name (keys %{$$attach{Info}}) {
    die "Field $f_name is not a valid field for $ati"
      if (!$e_info->{fields}->{$f_name});
    push @inf, SOAP::Data->name($f_name => $$attach{Info}{$f_name});
  }

  my $data = decode("utf8", $$attach{Data});
  my $soap = $self->{_at_soap};
  my $res = $soap->CreateAttachment(
    SOAP::Data->name("attachment" => \SOAP::Data->value(
    SOAP::Data->name(Info => \SOAP::Data->value(@inf))->attr({'xsi:type' => $ati}),
    SOAP::Data->name('Data')->value($data)->type('base64Binary'),
  ))->attr({'xsi:type' => $atb}));
  return $res->valueof('//CreateAttachmentResponse/CreateAttachmentResult');
}

# HIGH: Test this, this is just copied from create()
#       Need to read the API
sub delete {
  my ($self, @entities) = @_;

  die "Missing entity argument in call to delete" if (!@entities);

  # Validate that we have the right arguments.
  my @list;
  foreach my $ent (@entities) {
    $self->_validate_entity_argument($ent, 'delete');

    # Get the entity information if we don't already have it.
    $self->_load_entity_field_info(blessed($ent));

    # Verify all fields provided are valid.
    $self->_validate_fields($ent);

    push(@list, _entity_as_soap_data($ent));
  }

  my $soap = $self->{_at_soap};
  my $res = $soap->delete(SOAP::Data->name('Entities')->value(\SOAP::Data->name('array' => @list)))->result;

  if ($res->{Errors} || $res->{ReturnCode} ne '1') {
    # There were errors. Grab the errors and set $@ to their textual values.
    $self->_set_error($res->{Errors}->{ATWSError});
    return undef;
  }

  return _get_entity_results($res);
}

sub delete_attachment {
  my ($self, $id) = @_;

  my $soap = $self->{_at_soap};
  my $res = $soap->DeleteAttachment(SOAP::Data->name('attachmentId')->value($id))->result;
  if ($res) {
    $self->_set_error($res);
    return 0;
  }
  return 1;
}

# HIGH:  This function is needed
# Usage: $at->as_collection(sub{$_->cache->query})->expand->grep(sub{$_->{Ticket_ref_QueueID_name} == 'New'})->first->{id}
# Usage: my $query = $at->cache->query('Ticket');
#        $at->as_collection($query)->expand->grep(sub{$_->{Ticket_ref_QueueID_name} == 'New'})->first->{id}
#sub expand {
#  my ($self, $entity, $record) = @_;
#  $self->entity_info;
#  $self->get_field_info($entity)->grep(sub{$_->{IsReference} eq 'true'})->each(sub{
#    $record->{"$_->{Name}_ref"} = defined $_->{Name} && $_->{ReferenceEntityType} && defined $record->{$_->{Name}} ? join(':', $_->{ReferenceEntityType}, $record->{$_->{Name}}) : '';
#  });
#  $self->get_field_info($entity)->grep(sub{$_->{IsPickList} eq 'true'})->each(sub{
#    $record->{"$_->{Name}_name"} = defined $_->{Name} && defined $record->{$_->{Name}} ? $self->get_picklist_options($entity, $_->{Name}, Value => $record->{$_->{Name}}) : '';
#  });
#  $self->get_field_info($entity)->grep(sub{$_->{Type} eq 'datetime'})->each(sub{
#    return unless $record->{$_->{Name}};
#    $record->{$_->{Name}} =~ s/\.\d+$//;
#    eval { $record->{$_->{Name}} = Time::Piece->strptime($record->{$_->{Name}}, "%Y-%m-%dT%T"); };
#    delete $record->{$_->{Name}} if $@;
#  });
#  return $record;
#}

sub get_attachment {
  my ($self, $id) = @_;

  # The result is either a hashref with Data and Info or undef
  my $soap = $self->{_at_soap};
  my $res = $soap->GetAttachment(SOAP::Data->name('attachmentId')->value($id))->result;
  if ($res && %$res && $$res{Data}) {
    # Go ahead and decode it
    $$res{Data} = decode_base64($$res{Data});
  }
  return $res;
}

#sub _init {
#  my $self = shift;
#  $self->app->log->debug(sprintf 'pre-loading %s schemas', $self->entity_info->size);
#  $self->entity_info->each(sub{
#    my $entity = $_->{Name};
#    $self->attr($entity => sub {
#      my $info = Mojo::Collection->with_roles('+Hashes')->new(@{$self->_get_field_info($entity)});
#      $info->grep(sub{$_->{IsPickList} eq 'true' && ref $_->{PicklistValues} eq 'HASH' && ref $_->{PicklistValues}->{PickListValue} eq 'ARRAY'})->each(sub{
#        $_->{PickList} = Mojo::Collection->with_roles('+Hashes')->new(@{$_->{PicklistValues}->{PickListValue}});
#      });
#      return $info;
#    });
#  });
#  return $self;
#}

#sub get_entity_info {
#  my ($self, $entity) = @_;
#  return $entity ? $self->init->entity_info->grep(sub{$_->{Name} eq $entity}) : $self->init->entity_info;
#}
#sub _entity_info {
#  return Mojo::Collection->with_roles('+Hashes')->new(@{shift->_get_entity_info});
#}
#sub _get_entity_info {
#  my $self = shift;
#  $self->app->log->debug('getting entity info');
#  Mojo::DiskCache->new(home => $self->app->home, expire => 86_400 * 30)->cache(get_entity_info => sub {
#    my ($cache, $function) = @_;
#    $self->at->{at_soap}->GetEntityInfo->result->{EntityInfo};
#  });
#}
sub get_entity_info { shift->{_at_soap}->GetEntityInfo->result }

#sub get_field_info {
#  my ($self, $entity, $field) = @_;
#  die "missing entity" unless $entity;
#  return $field ? $self->init->$entity->grep(sub{$_->{Name} eq $field}) : $self->init->$entity;
#}
#sub _get_field_info {
#  my ($self, $entity) = @_;
#  $self->app->log->debug("getting $entity field info");
#  die "missing entity" unless $entity;
#  my $info = Mojo::DiskCache->new(home => $self->app->home, expire => 86_400 * 30)->cache(get_field_info => $entity, sub {
#    my ($cache, $function, $entity) = @_;
#    $self->at->{at_soap}->GetFieldInfo(SOAP::Data->name("psObjectType")->value($entity))->result->{Field};
#  });
#}

#sub get_picklist_options {
#  my ($self, $entity, $field, $kv, $vk) = @_;
#  die "missing entity" unless $entity;
#  die "missing field" unless $field;
#  my $picklist = $self->get_field_info($entity, $field)->map(sub{$_->{PickList}})->first;
#  return '' unless $picklist;
#  if ( $kv && defined $vk ) {
#    my $_kv = $kv eq 'Value' ? 'Label' : 'Value';
#    return $picklist->grep(sub{$_->{$kv} eq $vk})->map(sub{$_->{$_kv}})->first || '';
#  }
#  return $picklist;
#}
sub get_picklist_options {
  my ($self, $entity, $field) = @_;

  # See if we have this item cached.
  if (!exists($self->picklist_values->{$entity})) {
    $self->picklist_values->{$entity} = {};
  }
  if (!exists($self->picklist_values->{$entity}->{$field})) {
    # first get the entity information.
    $self->_load_entity_field_info($entity);

    # Next find the field inside this entity.
    my $data = $self->valid_entities->{$entity}->{fields}->{$field};

    if (!exists($data->{PicklistValues}) || ref($data->{PicklistValues}) ne 'HASH' ||
       !exists($data->{PicklistValues}->{PickListValue}) || ref($data->{PicklistValues}->{PickListValue}) ne 'ARRAY') {
      return ();
    }

    my %pick_list;
    foreach my $value (@{$data->{PicklistValues}->{PickListValue}}) {
      $pick_list{$value->{Label}} = $value->{Value};
    }

    $self->picklist_values->{$entity}->{$field} = \%pick_list;
  }

  return %{$self->picklist_values->{$entity}->{$field}};
}

sub get_threshold_and_usage_info {
  shift->{_at_soap}->getThresholdAndUsageInfo->result;
}

sub get_zone_info {
  my $self = shift;
  $self->{_at_soap}->getZoneInfo(SOAP::Data->value($self->username)->name('UserName'))->result;
}

sub new { shift->SUPER::new(@_)->_init_soap }

# LOW: Better logging and messaging
sub query {
  my $self = shift;
  my @args = @_;
  my ($entity, $query, $max_records, $limits) = (shift, shift || [], shift || $self->max_records, shift || $self->limits);

  # Validate that we have the right arguments.
  $self->_validate_entity_argument($entity, 'query');
  die "Missing query argument in call to query" unless ref $query eq 'ARRAY';

  # Get the entity information if we don't already have it.
  $self->_load_entity_field_info($entity);

  my $cache = $self->cache;
  my $name = $cache->name(query => \@args);
  my $short = $cache->short($name);
  my $data = $cache->retrieve($name);
  $data = ref $data eq 'ARRAY' ? $data : [];
  $data = {map { $_->{id} => $_ } @$data};
  my @since = $self->limits->since($entity => $cache->file($name)->tap(sub{$_=$_->stat->mtime if -e $_}));
  my @limits = $limits->limit($entity) if blessed($limits) && $limits->isa('Mojo::Autotask::Limits');
  my $last_id = 0;

  my $mu = Memory::Usage->new();
  $mu->record('init');
  while ( 1 ) {
    # We need to generate the QueryXML from the Query argument.
    my $_query = [
      {
        name => 'id',
        expressions => [{op => 'GreaterThan', value => "$last_id"}]
      },
      @since,
      @limits,
      @$query,
    ];

    #warn dumper($_query);
    my $query_xml = $self->_create_query_xml($entity, $_query);

    my $soap = $self->{_at_soap};
    my $res = $soap->query(SOAP::Data->value($query_xml)->name('sXML'))->result;
    if ($res->{Errors} || $res->{ReturnCode} ne '1') {
      # There were errors. Grab the errors and set $@ to their textual values.
      $self->_set_error($res->{Errors}->{ATWSError});
      return undef;
    }

    my @at = _get_entity_results($res);
    my $fetched = scalar @at;
    $self->log->debug(sprintf '[%s] Fetched %s results', $short, $fetched);
    last unless $fetched;
    $last_id = $at[-1]->{id}; # do they need to be sorted first or does Autotask always provide id-sorted results?
    $self->log->debug(sprintf '[%s] Kept %s results', $short, scalar @at);
    $self->log->debug(sprintf '[%s] %s', $short, "Last ID: $last_id");
    $self->log->debug(sprintf "[%s] Expanding $entity dataset and merging into %d existing records", $short, scalar keys %$data);
    warn sprintf "%s: %s", scalar keys %$data, total_size($data);
    #$data = {%$data, map { $_->{id} => $self->_expand($entity => $_) } @at};
    $data = {%$data, map { $_->{id} => $_ } @at};
    warn sprintf "%s: %s", scalar keys %$data, total_size($data);
    $mu->record(scalar keys %$data);
    $self->log->debug(sprintf '[%s] Max Records: %s (%s) / Max Memory: %s (%s)', $short, $max_records, scalar keys %$data, $self->max_memory, $mu->state->[-1]->[-1]);
    #$mu->dump;
    last if $fetched < $self->_api_records_per_query || scalar keys %$data >= $max_records || ($self->max_memory && $mu->state->[-1]->[-1] > $self->max_memory);
  }
  return [values %$data];
}

sub update {
  my ($self, @entities) = @_;

  die "Missing entity argument in call to update" if (!@entities);

  # Validate that we have the right arguments.
  my @list;
  foreach my $ent (@entities) {
    $self->_validate_entity_argument($ent, 'update');

    # Get the entity information if we don't already have it.
    $self->_load_entity_field_info(blessed($ent));

    # Verify all fields provided are valid.
    $self->_validate_fields($ent);

    push(@list, _entity_as_soap_data($ent));
  }

  my $soap = $self->{_at_soap};
  my $res = $soap->update(SOAP::Data->name('Entities')->value(\SOAP::Data->name('array' => @list)))->result;

  if ($res->{Errors} || $res->{ReturnCode} ne '1') {
    # There were errors. Grab the errors and set $@ to their textual values.
    $self->_set_error($res->{Errors}->{ATWSError});
    return undef;
  }

  return _get_entity_results($res);
}

###################

# LOW: Mojo::DOM should be able to do this
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

  return SOAP::Data->name(Entity => \SOAP::Data->value(@fields))->attr({'xsi:type' => ref($entity)});
}

# This function is used to return a consistent value: a list, not a ref
sub _get_entity_results {
  my ($result) = @_;

  # Make sure we have results to return.
  if (!exists($result->{EntityResults}) || ref($result->{EntityResults}) ne 'HASH' || !exists($result->{EntityResults}->{Entity})) {
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

sub _init_soap {
  my $self = shift;

  my $cache = $self->cache;

  # Create an empty hashref for the proxies arg if we don't already have one
  # defined.
  $self->{_proxies} = {};

  # MED: Replace SOAP::Lite transactions with non-blocking Mojo::UserAgent promise
  #      Only needed for processing XML (and even that could be replaced by Mojo::DOM)
  my $site = $self->soap_proxy->host;
  my $soap = $self->{_at_soap} = SOAP::Lite
    ->uri($self->ws_url->to_string)
    ->on_action(sub { return join('', @_)})
    ->proxy($self->soap_proxy->to_string,
      credentials => [
        "$site:443", $site, $self->username => $self->password
      ]);
  $self->{error} = '';

  # Check that we are using the right SOAP proxy.
  my $res = $cache->expires(86_400 * 30)->get_zone_info($self->username);
  if ($res->{Error} || $res->{ErrorCode}) {
    die sprintf "Could not find correct Autotask Proxy for user %s: %s", $self->username, $res->{ErrorCode};
  }
  # Set the proper URL base for ExecuteCommand
  $self->ec->zone(Mojo::URL->new($res->{WebUrl}));
  # See if our SOAP proxy matches the one provided.
  if ($self->soap_proxy ne $res->{URL}) {
    if (exists($self->{_proxies}->{$res->{URL}})) {
      die sprintf "Infinite recursion detected. We have already tried the SOAP proxy %s but have been directed to it again", $res->{URL};
    }
    $self->{_proxies}->{$self->soap_proxy} = 1;
    $self->soap_proxy(Mojo::URL->new($res->{URL}));
    return $self->new(username => $self->username, password => $self->password, soap_proxy => $self->soap_proxy, _proxies => $self->{_proxies});
  }

  # Get a list of all the entity types available.
  $res = $cache->expires(86_400 * 30)->get_entity_info($self->username);
  if (!exists($res->{EntityInfo}) || ref($res->{EntityInfo}) ne 'ARRAY') {
    die "Unable to get a list of valid Entities from the Autotask server";
  }
  foreach my $ent (@{$res->{EntityInfo}}) {
    $self->valid_entities->{$ent->{Name}} = $ent;
  }

  return $self;
}

sub _load_entity_field_info {
  my ($self, $entity) = @_;

  # If we have already loaded information for this entity, don't do it a
  # second time.
  return if $self->valid_entities->{$entity}->{fields};

  my $soap = $self->{_at_soap};

  # Now load the fields.
  my $res = $soap->GetFieldInfo(SOAP::Data->name('psObjectType')->value($entity))->result;
  foreach my $field (@{$res->{Field}}) {
    $self->valid_entities->{$entity}->{fields}->{$field->{Name}} = $field;
  }

  # Now load the user derfined fields.
  $res = $soap->getUDFInfo(SOAP::Data->name('psTable')->value($entity))->result;
  if ($res && ref($res) eq 'HASH' && exists($res->{Field}) && ref($res->{Field}) eq 'ARRAY') {
    foreach my $field (@{$res->{Field}}) {
      $self->valid_entities->{$entity}->{fields}->{$field->{Name}} = $field;
      $self->valid_entities->{$entity}->{fields}->{$field->{Name}}->{IsUDF} = 'true';
    }
  }

  return;
}

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

sub _parse_field {
  my ($self, $entity, $doc, $field) = @_;

  # Check to see that this entity actually has a field with this name.
  die "Invalid query field " . $field->{name} . " for entity $entity"
    if (!$self->valid_entities->{$entity}->{fields}->{$field->{name}}->{IsQueryable});
  my $f_elem = $doc->createElement('field');
  if ($self->valid_entities->{$entity}->{fields}->{$field->{name}}->{IsUDF}) {
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
  elsif ( !grep {$_ eq $e_type} keys(%{$self->valid_entities}) ) {
    die "$e_type is not a valid entity. Valid entities are: " .
        join(', ', keys(%{$self->valid_entities}))
  }
  elsif ($self->valid_entities->{$e_type}->{$flag} eq 'false') {
    die "Not allowed to $type $e_type"
  }

  return 1;
}

sub _validate_fields {
  my ($self, $ent) = @_;

  my $type = blessed($ent);
  my $e_info = $self->valid_entities->{$type};

  foreach my $f_name (keys(%$ent)) {
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
