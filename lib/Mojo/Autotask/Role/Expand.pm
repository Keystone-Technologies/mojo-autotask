package Mojo::Autotask::Role::Expand;
use Mojo::Base -role;

use Mojo::Util 'dumper';

use Time::Piece;

# $at->cache_c->query('Ticket')->expand($at, ['ResourceID'])->grep(sub{$_->{ResourceID_ref_Name} eq 'John'})->size;
sub expand {
  my ($self, $at, @args) = @_;
  return $self unless $at;

  my $data = {};
  $self->each(sub {
    my ($entity, $record) = (ref $_, $_);
    $at->get_field_info_c($entity)->grep(sub{$_->{IsReference} eq 'true'})->each(sub{
      $record->{"$_->{Name}_ref"} = defined $_->{Name} && $_->{ReferenceEntityType} && defined $record->{$_->{Name}} ? join(':', $_->{ReferenceEntityType}, $record->{$_->{Name}}) : '';
    });
    $at->get_field_info_c($entity)->grep(sub{$_->{IsPickList} eq 'true'})->each(sub{
      $record->{"$_->{Name}_name"} = defined $_->{Name} && defined $record->{$_->{Name}} ? $at->get_picklist_options($entity, $_->{Name}, Value => $record->{$_->{Name}}) : '';
    });
    $at->get_field_info_c($entity)->grep(sub{$_->{Type} eq 'datetime'})->each(sub{
      return unless $record->{$_->{Name}};
      $record->{$_->{Name}} =~ s/\.\d+$//;
      eval { $record->{$_->{Name}} = Time::Piece->strptime($record->{$_->{Name}}, "%Y-%m-%dT%T"); };
      delete $record->{$_->{Name}} if $@;
    });
    $_ = $record;
  })->map(sub {
    # $at->query()->expand($at, [qw/a b c/]);
    # $at->query()->expand($at, 'a');
    foreach my $arg ( grep { !ref $_ || ref $_ eq 'ARRAY' } @args ) {
      foreach my $col ( ref $arg ? @$arg : $arg ) {
        last unless $col;
        $col.='_ref' unless $col =~ /_ref$/;
        next unless $_->{$col};
        my ($entity, $id) = split /:/, $_->{$col};
        next unless $entity && defined $id;
        $data->{$entity} ||= $at->query($entity)->hashify('id');
        foreach my $l ( keys %{$data->{$entity}->{$id}} ) {
          $_->{"${col}_$l"} = $data->{$entity}->{$id}->{$l};
        }
      }
    }
    # $at->query()->expand($at, {a => 'a1'});
    # $at->query()->expand($at, {a => {}});
    # $at->query()->expand($at, {a => [qw/a b c/, {}]});
    foreach my $arg ( grep { ref $_ eq 'HASH' } @args ) {
      while ( my ($col, $options) = each %$arg ) {
        last unless $col;
        $col.='_ref' unless $col =~ /_ref$/;
        next unless $_->{$col};
        my ($entity, $id) = split /:/, $_->{$col};
        next unless $entity && defined $id;
        my @query = grep { ref eq 'HASH' } ref $options eq 'ARRAY' ? @$options : $options;
        $data->{$entity} ||= $at->query($entity, [@query])->hashify('id');
        my @lookup = grep { ref eq 'ARRAY' || ! ref } ref $options eq 'ARRAY' ? @$options : $options;
        foreach my $l ( @lookup ) {
          $_->{"${col}_$l"} = $data->{$entity}->{$id}->{$l};
        }
      }
    }
  });

  return $self;
}

sub to_date {
  my ($self, $format) = @_;
  $format ||= '%m/%d/%Y %H:%M:%S';
  $self->each(sub{
    my $h = $_;
    $h->{$_} = $h->{$_}->strftime($format) foreach grep { ref $h->{$_} eq 'Time::Piece' } keys %$h;
  });
}

1;

=encoding utf8

=head1 NAME 

Mojo::Autotask::Role::Expand - 

=head1 SYNOPSIS

  ...

=head1 DESCRIPTION

...

=head1 METHODS

=head2 expand

  $collection = $collection->expand(...);

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
