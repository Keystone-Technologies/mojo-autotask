package Data::Table::Role::Roles;
use Mojo::Base -role;

sub pat {
  my ($self, $cb) = (shift, shift);
  $_=$_->$cb(@_) for $self;
  return $self;
}
sub tap        { shift->Mojo::Base::tap(@_) }
sub with_roles { shift->Mojo::Base::with_roles(@_) }

1;
