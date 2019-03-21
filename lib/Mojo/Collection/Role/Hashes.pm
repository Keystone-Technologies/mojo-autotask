package Mojo::Collection::Role::Hashes;
use Mojo::Base -role;

our $VERSION = '0.01';

use Mojo::Util 'dumper';

requires 'grep';
requires 'map';
requires 'sort';

sub addkey    { my ($self, $key, $value) = @_; $self->each(sub{$_->{$key} = $value}) }
sub sortkey   { my ($self, $key) = @_; $self->sort(sub{$a->{$key} cmp $b->{$key}}) }
sub nsortkey  { my ($self, $key) = @_; $self->sort(sub{$a->{$key} <=> $b->{$key}}) }
sub grepkey   { my ($self, $key, $qr) = @_; $self->grep(sub{$qr ? $_->{$key} =~ qr($qr) : $_->{$key}}) }
sub mapkey    { my ($self, $key) = @_; $self->map(sub{$_->{$key}}) }
sub dump      { $#_ > 0 ? dumper shift->slice(@_) : dumper shift }
sub stringify { shift->each(sub{my $h=$_; $h->{$_} = "$h->{$_}" foreach keys %$h}) }
sub keep      { my ($self, @keys) = @_; $self->each(sub{my $h=$_; my $h1={}; $h1->{$_} = delete $h->{$_} foreach @keys; $_=$h1}) }
sub discard   { my ($self, @keys) = @_; $self->each(sub{delete @$_{@keys} }) }
sub hashify   {
  my ($self, $key) = @_;
  die "missing key in hashify()" unless $key;
  my $data = {};
  $self->each(sub{$data->{$_->{$key}} = $_});
  return $data;
}
sub rename {
  my $self = shift;
  local %_ = @_;
  $self->each(sub{
    while ( my ($old, $new) = each %_ ) {
      $_->{$new} = delete $_->{$old}
    }
  });
}

sub sum_by {
  my ($self, $sum, $keys) = @_;
  $self->with_roles('+UtilsBy')->new(map { $_->reduce(sub { $a->{$sum} += $b->{$sum}; $a }) } values %{$self->partition_by(sub { my $a = $_; join '', map { $a->{$_} } @$keys })});
}

sub tsv {
  my ($self, $headers, $options) = @_;
  #return unless ref $self->first eq 'HASH';
  $options ||= {};
  @$headers = map { $_=>$_ } sort keys %{$self->first} unless $headers;
  my $c=-1;
  @$headers = map { $c++; ($c&1)&&/^-$/?$headers->[$c-1]:$_} @$headers[0..$#$headers];
  my @names = @$headers[grep { !($_ & 1) } 0 .. $#$headers];
  my @labels = @$headers[grep { ($_ & 1) } 0 .. $#$headers];
  my $csv = $self->new(@$self);
  unshift @$csv, {@$headers} if ref $headers eq 'ARRAY';
  $csv = $csv->map(sub{my $h=$_; $_ = join $options->{d}||"\t", map { substr(($h->{$_}//''),0,$options->{l}||length($h->{$_}//'')) =~ s/[\n\t].*?//sgr } ref $headers eq 'ARRAY' ? @names : sort keys %$h})->join($options->{r}||"\n");
}

1;
