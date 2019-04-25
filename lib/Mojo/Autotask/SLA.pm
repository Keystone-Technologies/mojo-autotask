package Mojo::Autotask::SLA;
use Mojo::Base -base;

use Time::Piece;
use Time::Seconds;
use DateTime;
 
has hours => sub {{
  0 => [undef, undef],
  1 => ['07:30', '17:00'],
  2 => ['07:30', '17:00'],
  3 => ['07:30', '17:00'],
  4 => ['07:30', '17:00'],
  5 => ['07:30', '17:00'],
  6 => [undef, undef],
}};
has holidays => sub {[
  qw(2018-11-22 2018-12-25 2019-01-01)
]};
has parse_format => '%m/%d/%Y %H:%M:%S';

sub calc1 {
  my ($self, $start, $end) = @_;
  $start = Time::Piece->strptime($start, $self->parse_format) unless _isa($start => 'Time::Piece');
  $end   = Time::Piece->strptime($end,   $self->parse_format) unless _isa($end   => 'Time::Piece');
  my $b = my $nb = 0;
my $c=0;
  while ( $start < $end ) {
warn $start;
    if ( $self->_is_business($start) ) {
      $b += $self->_next_non_business(\$start);
warn $b;
    } else {
      $nb += $self->_next_business(\$start);
warn $nb;
    }
warn $start;
exit if $c++==5;
  }
  return $b;
}

sub _is_business {
  my ($self, $start) = @_;
  return 0 if $self->_holiday($start->ymd);
  return 0 unless defined $self->hours->{$start->day_of_week}->[0] && $self->hours->{$start->day_of_week}->[1];
  return 0 if _hms1($start->hms) >= _hms1($self->hours->{$start->day_of_week}->[1]);
  return 0 if _hms1($start->hms) <  _hms1($self->hours->{$start->day_of_week}->[0]);
  return 1;
}

sub _hms1 { @_ = split /:/, shift; $_[0]*3600+$_[1]*60+($_[2]||0) }

sub _next_non_business {
  my ($self, $start) = @_;
  my $_start = $$start->epoch;
  $$start = $$start - _hms1($$start->hms) + _hms1($self->hours->{$$start->day_of_week}->[1]);
#warn $$start;
  return $$start->epoch - $_start;
}

sub _next_business {
  my ($self, $start) = @_;
  my $_start = $$start->epoch;
  $$start = $$start + (_hms1('23:59:59') - _hms1($$start->hms)) + _hms1($self->hours->{$$start->day_of_week}->[0]);
#warn $$start;
  return $$start->epoch - $_start;
}

sub calc {
  my ($self, $start, $end) = @_;
  $start = Time::Piece->strptime($start, $self->parse_format) unless _isa($start => 'Time::Piece');
  $end   = Time::Piece->strptime($end,   $self->parse_format) unless _isa($end   => 'Time::Piece');
  my $s = 0;
  while ( $start < $end ) {
#warn $start;
    $start = _round($start + ONE_DAY, ONE_HOUR) and next if $self->_holiday($start->ymd);
    $start = _round($start + ONE_DAY, ONE_HOUR) and next unless defined $self->hours->{$start->day_of_week}->[0] && $self->hours->{$start->day_of_week}->[1];
    $start = _round($start + ONE_HOUR, ONE_HOUR / 2) and next if _hms($start->hms) > _hms($self->hours->{$start->day_of_week}->[1]) &&
                                           _hms($start->hms) + ONE_HOUR - ONE_DAY < _hms($self->hours->{$start->day_of_week}->[0]);
    $start = _round($start + ONE_HOUR, ONE_HOUR / 2) and next if _hms($start->hms) < _hms($self->hours->{$start->day_of_week}->[0]) &&
                                           _hms($start->hms) + ONE_HOUR < _hms($self->hours->{$start->day_of_week}->[0]);
    $start = $start + ONE_MINUTE and $s += ONE_MINUTE;# if _hms($start->hms) >= _hms($self->hours->{$start->day_of_week}->[0]) && _hms($start->hms) <= _hms($self->hours->{$start->day_of_week}->[1]);
  }
  return $s;
}

sub _holiday { my ($self, $holiday) = @_; grep { $_ eq $holiday } @{$self->holidays} }
sub _hms { @_ = split /:/, shift; $_[0]*3600+$_[1]*60 }
sub _isa { ref $_[0] && $_[0]->isa($_[1]) }
sub _round {
  my ($tod, $round) = @_;
  return $tod - (int($tod->epoch) % int($round));
}

1;
