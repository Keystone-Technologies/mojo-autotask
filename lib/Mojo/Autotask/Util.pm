package Mojo::Autotask::Util;
use Mojo::Base -strict;

use Exporter 'import';
use Role::Tiny;
use Time::Piece;

Role::Tiny->apply_roles_to_package('Time::Piece', 'Time::Piece::Role::More');

our @EXPORT_OK = qw(filter in_list localtime);

sub filter {
  return map { {name => $_->[0], expressions => [{op => $_->[1], value => $_->[2]}]} } @_;
}

sub in_list {
  my ($name, $op) = @_;
  return
  {
    elements => [
      {
        name => $name,
        expressions => [{op => $op, value => "$_[0]"}]
      }
    ]
  },
  (map {
    {
      operator => 'OR',
      elements => [
        {
          name => $name,
          expressions => [{op => $op, value => "$_"}]
        }
      ]
    }
  } grep { $_ } @_[1..199])
}

1;
