package Mojo::Autotask::Util;
use Mojo::Base -strict;

use Exporter 'import';
use Role::Tiny;
use Time::Piece;

Role::Tiny->apply_roles_to_package('Time::Piece', 'Time::Piece::Role::Autotask');

our @EXPORT_OK = qw(filter filter_a in_list in_list_a localtime parse_datetime strip_ms);

sub filter {
  return map { {name => $_->[0], expressions => [{op => $_->[1], value => $_->[2]}]} } @_;
}

sub filter_a { [filter(@_)] }

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

sub in_list_a { [in_list(@_)] }

sub parse_datetime {
  my $dt = shift;
  if ( length($dt) == length('YYYY-mm-ddTHH:MM:SS') ) {
    localtime->strptime($dt, '%Y-%m-%dT%T');
  } elsif ( length($dt) > length('YYYY-mm-ddTHH:MM:SS') ) {
    # Need to add 1 to timestamp because the timestamp field is in
    # milliseconds and needs to be rounded up
    localtime->strptime(strip_ms($dt), '%Y-%m-%dT%T') + 1;
  }
}

sub strip_ms { substr(shift, 0, length('YYYY-mm-ddTHH:MM:SS')) }

1;
