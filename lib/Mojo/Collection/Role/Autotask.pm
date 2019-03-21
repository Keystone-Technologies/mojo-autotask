package Mojo::Collection::Role::Autotask;
use Mojo::Base -role;

use Mojo::Autotask::Util 'localtime';
use Mojo::JSON 'j';
use Mojo::Util qw/b64_encode dumper md5_sum/;

use Data::Table;
use Role::Tiny;
use Scalar::Util 'blessed';

use constant DEBUG => $ENV{MOJO_AUTOTASK_DEBUG} || 0;

requires 'map';

Role::Tiny->apply_roles_to_package('Data::Table', 'Data::Table::Role::Roles');

sub collapse {
  my $self = shift;
  $self->map(sub {
    my $record = $_;
    my $original = $_->{_original};
    $original->{$_} = $record->{$_} for grep { $_ ne 'id' } keys %$original;
    $_ = $original;
  });
}

# $at->query('Ticket')->expand($at, ['ResourceID'])->grep(sub{$_->{ResourceID_ref_Name} eq 'John'})->size;
sub expand {
  my ($self, $at, @args) = @_;
  return $self unless blessed $at && $at->isa('Mojo::Autotask');

  my @expand = grep { !ref } @args;
  push @expand, map { @$_ } grep { ref eq 'ARRAY' } @args;
  foreach my $h ( grep { ref eq 'HASH' } @args ) {
    push @expand, map { {$_ => $h->{$_}} } keys %$h;
  }

  my $entities = {};
  foreach my $entity ( keys %{$at->entities} ) {
    my $fields = $at->entities->{$entity}->{fields};
    $entities->{$entity} = Mojo::Collection->new(values %$fields);
  }

  warn '-- Expanding' if DEBUG;
  my $data = {};
  $self->map(sub {
    my ($entity, $record) = (ref $_, $_);
    $record->{_original} = $record;
    $entities->{$entity}->grep(sub{$_->{IsReference} eq 'true'})->each(sub{
      $record->{"$_->{Name}_ref"} = defined $_->{Name} &&
      $_->{ReferenceEntityType} &&
      defined $record->{$_->{Name}} ?
        join(':', $_->{ReferenceEntityType}, $record->{$_->{Name}}) :
        '';
    });
    $entities->{$entity}->grep(sub{$_->{IsPickList} eq 'true'})->each(sub{
      $record->{"$_->{Name}_name"} = defined $_->{Name} &&
      defined $record->{$_->{Name}} ?
        $at->get_picklist_options($entity, $_->{Name}, Value => $record->{$_->{Name}}) :
        '';
    });
    $entities->{$entity}->grep(sub{$_->{Type} eq 'datetime'})->each(sub{
      return unless $record->{$_->{Name}} && !ref $record->{$_->{Name}};
      $record->{$_->{Name}} =~ s/\.\d+$//;
      eval { $record->{$_->{Name}} = localtime->strptime($record->{$_->{Name}}, "%Y-%m-%dT%T"); };
      delete $record->{$_->{Name}} if $@;
    });
    if ( $record->{UserDefinedFields} && $record->{UserDefinedFields}->{UserDefinedField} && ref $record->{UserDefinedFields}->{UserDefinedField} eq 'ARRAY' ) {
      $record->{"UDF_$_->[0]"} = $_->[1]
        foreach map { [$_->{Name} =~ s/\W/_/gr, $_->{Value}||''] }
                grep { ref eq 'HASH' }
                @{$record->{UserDefinedFields}->{UserDefinedField}};
      delete $record->{UserDefinedFields};
    }
    return $_ = $record unless @expand;

    # $at->query()->expand($at, [qw/a b c/]);
    # $at->query()->expand($at, 'a');
    # $at->query()->expand($at, {a => 'a1'});
    # $at->query()->expand($at, {a => {}});
    # $at->query()->expand($at, {a => [qw/a b c/, {}]});
    foreach ( @expand ) {
      my ($col, $options) = ref ? each %$_ : ($_, []);
      next unless $col;
      $col.='_ref' unless $col =~ /_ref$/;
      next unless $record->{$col};
      my ($entity, $id) = split /:/, $record->{$col};
      next unless $entity && defined $id;
      my $query = [grep { ref eq 'HASH' } @$options];
      my @keys  = grep { !ref || ref eq 'ARRAY' } @$options;
      my $cache = md5_sum(b64_encode(j([$entity => $query])));
      $data->{$cache} ||= $at->query_all($entity => $query)->expand($at)->hashify('id');
      foreach my $k ( @keys ? @keys : keys %{$data->{$cache}->{$id}} ) {
        $record->{"${col}_$k"} = $data->{$cache}->{$id}->{$k};
      }
    }
    $_ = $record;
  });
}

sub restore { shift->map(sub { $_ = $_->{_original} }) }

# tablify() will always return a Mojo::ByteStream which can be tap()'d
# $c->grep()->tablify($columns, [qw/+Sparklines +Text/], sub{$_->group->pivot->text(sub{$_->add("ABC")})->tap(sub{$ua->post('/upload') and $sendgrid->send})->to_string;
sub tablify {
  my ($self, $columns) = (shift, shift);
  @$columns = map { $_ } sort keys %{$self->first} unless $columns;
  return Data::Table->new($self->map(sub{my $data=$_; ref $data eq 'ARRAY' ? [@$_[0..$#$columns-1]] : [map{$data->{$_}}@$columns]})->to_array, $columns);
}

sub to_date {
  my ($self, $format) = @_;
  $format ||= '%m/%d/%Y %H:%M:%S';
  $self->map(sub{
    my $record = $_;
    $record->{$_} = $record->{$_}->strftime($format)
      foreach grep { _isa($record->{$_} => 'Time::Piece') } keys %$record;
    $_ = $record;
  });
}

sub _isa { blessed($_[0]) && $_[0]->isa($_[1]) }

1;

=encoding utf8

=head1 NAME 

Mojo::Autotask::Role::Expand - 

=head1 SYNOPSIS

  ...

=head1 DESCRIPTION

...

=head1 METHODS

=head2 collapse

  $collection = $collection->collapse;

...

=head2 expand

  $collection = $collection->expand(...);

...

=head2 restore

  $collection = $collection->restore;

...

=head2 to_date

  $collection = $collection->to_date($format);

Expects a collection of hashes and for each key in the hash that is a
L<Time::Piece> instance, returns a L<Time::Piece/"strftime"> formatted
string.

  $collection = $collection->to_date('%Y-%m-%dT%H:%M:%S');

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Autotask>

=cut
