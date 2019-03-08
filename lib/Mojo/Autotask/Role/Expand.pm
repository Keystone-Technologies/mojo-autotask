package Mojo::Autotask::Role::Expand;
use Mojo::Base -role;

use Mojo::Autotask::Util 'localtime';
use Mojo::JSON 'j';
use Mojo::Util qw/b64_encode dumper md5_sum/;

use Scalar::Util 'blessed';

requires 'map';

# $at->query('Ticket')->expand($at, ['ResourceID'])->grep(sub{$_->{ResourceID_ref_Name} eq 'John'})->size;
sub expand {
  my ($self, $at, @args) = @_;
  return $self unless blessed $at && $at->isa('Mojo::Autotask');

  my @expand = grep { !ref } @args;
  push @expand, map { @$_ } grep { ref eq 'ARRAY' } @args;
  foreach my $h ( grep { ref eq 'HASH' } @args ) {
    push @expand, map { {$_ => $h->{$_}} } keys %$h;
  }

  my $data = {};
  $self->map(sub {
    my ($entity, $record) = (ref $_, $_);
    $at->entities->{$entity}->grep(sub{$_->{IsReference} eq 'true'})->each(sub{
      $record->{"$_->{Name}_ref"} = defined $_->{Name} && $_->{ReferenceEntityType} && defined $record->{$_->{Name}} ? join(':', $_->{ReferenceEntityType}, $record->{$_->{Name}}) : '';
    });
    $at->entities->{$entity}->grep(sub{$_->{IsPickList} eq 'true'})->each(sub{
      $record->{"$_->{Name}_name"} = defined $_->{Name} && defined $record->{$_->{Name}} ? $at->get_picklist_options($entity, $_->{Name}, Value => $record->{$_->{Name}}) : '';
    });
    $at->entities->{$entity}->grep(sub{$_->{Type} eq 'datetime'})->each(sub{
      return unless $record->{$_->{Name}} && !ref $record->{$_->{Name}};
      $record->{$_->{Name}} =~ s/\.\d+$//;
      eval { $record->{$_->{Name}} = localtime->strptime($record->{$_->{Name}}, "%Y-%m-%dT%T"); };
      delete $record->{$_->{Name}} if $@;
    });
    if ( $record->{UserDefinedFields} ) {
      $record->{"UDF_$_->[0]"} = $_->[1] foreach map { [$_->{Name} =~ s/\W/_/gr, $_->{Value}||''] } grep { ref eq 'HASH' } @{$record->{UserDefinedFields}->{UserDefinedField}};
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
      $data->{$cache} ||= $at->query($entity => $query)->expand($at)->hashify('id');
      foreach my $k ( @keys ? @keys : keys %{$data->{$cache}->{$id}} ) {
        $record->{"${col}_$k"} = $data->{$cache}->{$id}->{$k};
      }
    }
    $_ = $record;
  });
}

sub to_date {
  my ($self, $format) = @_;
  $format ||= '%m/%d/%Y %H:%M:%S';
  $self->map(sub{
    my $h = $_;
    $h->{$_} = $h->{$_}->strftime($format) foreach grep { ref $h->{$_} eq 'Time::Piece' } keys %$h;
    $_ = $h;
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
