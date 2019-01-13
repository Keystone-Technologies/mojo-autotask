package Mojo::Autotask::Role::Tablify;
use Mojo::Base -role;

use Role::Tiny;
use Data::Table;

# tablify() will always return a Mojo::ByteStream which can be tap()'d
# $c->grep()->tablify($columns, [qw/+Sparklines +Text/], sub{$_->group->pivot->text(sub{$_->add("ABC")})->tap(sub{$ua->post('/upload') and $sendgrid->send})->to_string;
sub tablify {
  my ($self, $columns) = (shift, shift);
  @$columns = map { $_ } sort keys %{$self->first} unless $columns;
  Role::Tiny->apply_roles_to_package('Data::Table', 'Mojo::Base::Role::Base');
  return Data::Table->new($self->map(sub{my $data=$_; ref $data eq 'ARRAY' ? [@$_[0..$#$columns-1]] : [map{$data->{$_}}@$columns]})->to_array, $columns);
}

1;
