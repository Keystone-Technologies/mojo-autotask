package Time::Piece::Role::Autotask;
use Mojo::Base -role, -signatures;

use Time::Piece;
use Time::Seconds;
use DateTime;

my (
  %quarters,
  %days,
);
 
BEGIN {
  %quarters = (
    1 => [qw/01-01 03-31/],
    2 => [qw/01-01 03-31/],
    3 => [qw/01-01 03-31/],
    4 => [qw/04-01 06-30/],
    5 => [qw/04-01 06-30/],
    6 => [qw/04-01 06-30/],
    7 => [qw/07-01 09-30/],
    8 => [qw/07-01 09-30/],
    9 => [qw/07-01 09-30/],
    10 => [qw/10-01 12-31/],
    11 => [qw/10-01 12-31/],
    12 => [qw/10-01 12-31/],
  );
  %days = (
    'sunday' => 0,
    'monday' => 1,
    'tuesday' => 2,
    'wednesday' => 3,
    'thursday' => 4,
    'friday' => 5,
    'saturday' => 6,
  );
}

sub tomorrow { shift() + ONE_DAY }
sub today { shift() }
sub yesterday { shift() - ONE_DAY }
sub add_days { shift() + ONE_DAY * pop }
sub add_weeks { shift() + ONE_DAY * 7 * pop }
sub add_years { shift->add_months(12*pop) }
sub date_only ($self) { $self->_new_from_string($self->ymd, "%Y-%m-%d") }
*no_time = \&date_only;
sub first_day_of_current_month ($self) { $self->_new_from_string($self->strftime("%Y-%m-01")) }
sub last_day_of_current_month ($self) { $self->_new_from_string($self->strftime(sprintf "%%Y-%%m-%s", $self->month_last_day)) }
sub first_day_of_last_month ($self) { $self->_new_from_string($self->add_months(-1)->strftime("%Y-%m-01")) }
sub last_day_of_last_month ($self) { $self->_new_from_string($self->add_months(-1)->strftime(sprintf "%%Y-%%m-%s", $self->add_months(-1)->month_last_day)) }
sub first_day_of_next_month ($self) { $self->_new_from_string($self->add_months(1)->strftime("%Y-%m-01")) }
sub last_day_of_next_month ($self) { $self->_new_from_string($self->add_months(1)->strftime(sprintf "%%Y-%%m-%s", $self->add_months(1)->month_last_day)) }
sub first_day_of_current_year ($self) { $self->_new_from_string($self->strftime("%Y-01-01")) }
sub last_day_of_current_year ($self) { $self->_new_from_string($self->strftime("%Y-12-31")) }
sub first_day_of_last_year ($self) { $self->_new_from_string($self->add_years(-1)->strftime("%Y-01-01")) }
sub last_day_of_last_year ($self) { $self->_new_from_string($self->add_years(-1)->strftime("%Y-12-31")) }
sub first_day_of_next_year ($self) { $self->_new_from_string($self->add_years(1)->strftime("%Y-01-01")) }
sub last_day_of_next_year ($self) { $self->_new_from_string($self->add_years(1)->strftime("%Y-12-31")) }
sub quarter ($self) { $quarters{$self->mon} }
sub last_quarter ($self) { $quarters{$self->add_months(-3)->mon} }
sub next_quarter ($self) { $quarters{$self->add_months(3)->mon} }
sub first_day_of_current_quarter ($self) { $self->_new_from_string($self->strftime(sprintf "%%Y-%s", $quarters{$self->mon}[0])) }
sub last_day_of_current_quarter ($self) { $self->_new_from_string($self->strftime(sprintf "%%Y-%s", $quarters{$self->mon}[1])) }
sub first_day_of_last_quarter ($self) { $self->_new_from_string($self->add_months(-3)->strftime(sprintf "%%Y-%s", $quarters{$self->add_months(-3)->mon}[0])) }
sub last_day_of_last_quarter ($self) { $self->_new_from_string($self->add_months(-3)->strftime(sprintf "%%Y-%s", $quarters{$self->add_months(-3)->mon}[1])) }
sub first_day_of_next_quarter ($self) { $self->_new_from_string($self->add_months(3)->strftime(sprintf "%%Y-%s", $quarters{$self->add_months(3)->mon}[0])) }
sub last_day_of_next_quarter ($self) { $self->_new_from_string($self->add_months(3)->strftime(sprintf "%%Y-%s", $quarters{$self->add_months(3)->mon}[1])) }
sub current_week ($self, $day) { $self->_new_from_string($self->add_days(-1 * ($self->day_of_week - $days{lc($day||$self->fullday)}))->ymd) }
sub last_week ($self, $day=undef) { $self->_new_from_string($self->add_days(-7)->add_days(-1 * ($self->day_of_week - $days{lc($day||$self->fullday)}))->ymd) }
sub next_week ($self, $day=undef) { $self->_new_from_string($self->add_days(7)->add_days(-1 * ($self->day_of_week - $days{lc($day||$self->fullday)}))->ymd) }
#sub l ($self, $day=undef) { $self->_new_from_string($self->add_days(-7)->add_days(-1 * ($self->day_of_week - $days{lc($day||$self->fullday)}))->ymd) }

sub _new {
  shift->localtime(shift->epoch)
}
sub _new_from_string {
  shift->strptime(shift, shift || '%Y-%m-%d')
}

1;

=encoding utf8

=head1 NAME

Time::Piece::Role::Autotask - Add some additional date calculation methods to Time::Piece as roles

=head1 SYNOPSIS

  use WithRoles;
  use Time::Piece;

  with_roles("Time::Piece", "+Autotask");
  say localtime->add_days(2)->add_years(4)->reset->today'

  with_roles("Time::Piece");
  say localtime->with_roles('+Autotask')->add_days(2)->add_years(4)->reset->today'

=head1 DESCRIPTION

L<Time::Piece::Role::Autotask> is a simple role class for L<Time::Piece> projects with fluent
interfaces.

  # use WithRoles;
  use strict;
  use warnings;
  use utf8;
  use feature ':5.10';
  use IO::Handle ();
  use Role::Tiny;
  sub has { Mojo::Base::attr(__PACKAGE__, @_) }

This will also disable experimental warnings on versions of Perl where this
feature was still experimental.

=head1 METHODS

L<Time::Piece> implements the following methods.

=head2 with_roles

  my $new_class = with_roles('SubClass');
  my $object    = $new_class->with_roles('SubClass::Role::One')->one;

  my $new_class = with_roles('SubClass', 'SubClass::Role::One');
  my $Object    = $new_class->one;

Create a new class with one or more L<Role::Tiny> roles. If called on a class
returns the new class, or if called on an object reblesses the object into the
new class. For roles following the naming scheme C<MyClass::Role::RoleName> you
can use the shorthand C<+RoleName>. Note that role support depends on
L<Role::Tiny> (2.000001+).

  # Create a new class with the role "SubClass::Role::Foo" and instantiate it
  my $new_class = SubClass->with_roles('+Foo');
  my $object    = $new_class->new;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
