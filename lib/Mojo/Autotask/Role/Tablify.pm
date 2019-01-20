package Mojo::Autotask::Role::Tablify;
use Mojo::Base -role;

use Role::Tiny;
use Data::Table;

Role::Tiny->apply_roles_to_package('Data::Table', 'Mojo::Base::Role::Base');

# tablify() will always return a Mojo::ByteStream which can be tap()'d
# $c->grep()->tablify($columns, [qw/+Sparklines +Text/], sub{$_->group->pivot->text(sub{$_->add("ABC")})->tap(sub{$ua->post('/upload') and $sendgrid->send})->to_string;
sub tablify {
  my ($self, $columns) = (shift, shift);
  @$columns = map { $_ } sort keys %{$self->first} unless $columns;
  return Data::Table->new($self->map(sub{my $data=$_; ref $data eq 'ARRAY' ? [@$_[0..$#$columns-1]] : [map{$data->{$_}}@$columns]})->to_array, $columns);
}

1;

=encoding utf8

=head1 NAME 

Mojo::Autotask::Role::Tablify - 

=head1 SYNOPSIS

  ...

=head1 DESCRIPTION

...

=head1 METHODS

=head2 tablify

  $collection = $collection->tablify(...);

...

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Autotask>

=cut
