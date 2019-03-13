# $ perl -Mlib=lib -MTime::Piece -MMojo::Util=dumper -MMojo::Autotask::Limits -E 'my $l = Mojo::Autotask::Limits->new(entity => 'Ticket', last_activity => localtime->add_months(-3), Ticket => 36); say dumper(\@$l)'

package Mojo::Autotask::Query;
use Mojo::Base -base;

use overload
  '@{}'      => sub {
                  my $self = shift;
                  [$self->_last_id, $self->_last_activity, $self->_start_date, @{$self->query}]
                },
  'fallback' => 1;

use Mojo::Autotask::Util 'localtime';
use Mojo::JSON 'j';
use Mojo::Util 'md5_sum';

use Scalar::Util 'blessed';

has at            => sub { die };
has entity        => sub { die };
has expire        => 900;
has last_activity => undef;
has last_id       => 0;
has now           => undef;
has query         => sub { [] };
has refresh       => undef;
has start_date    => sub {
  my $self = shift;
  my $entity = $self->entity;
  return undef unless my $months = $self->$entity;
  return $self->_localtime->add_months($months * -1);
};

has Account => undef;
has AccountNote => 12;
has AccountToDo => 12;
has Appointment => 12;
has BillingItem => 12;
has Contact => undef;
has ContractCost => 48;
has ContractMilestone => 48;
has ContractNote => 48;
has Currency => undef;
has InstalledProduct => 12;
has Invoice => 12;
has Opportunity => 48;
has Phase => 24;
has Project => 24;
has ProjectCost => 24;
has ProjectNote => 24;
has PurchaseOrder => 48;
has Quote => 48;
has QuoteTemplate => undef;
has Service => undef;
has ServiceBundle => undef;
has ServiceCall => 12;
has Task => 12;
has TaskNote => 12;
has Ticket => 12;
has TicketCost => 12;
has TicketNote => 12;
has TimeEntry => 12;
has UserDefinedFieldDefinition => undef;
has UserDefinedFieldListItem => undef;

sub key {
  my $self = shift;
  my $key = md5_sum(j([$self->_start_date, @{$self->query}]));
  return join ':', '@MT' => (ref($self) || $self), $self->at->username, $self->at->tracking_id, $self->entity, $key;
}

sub new {
  my $self = shift;
  $self->SUPER::new((ref $self ? (at => $self->at) : ()), @_ ? @_ > 1 ? @_ : %{$_[0]} : ());
}

sub _last_activity {
  my $self = shift;
  return () unless my $t = $self->last_activity;
  return () unless $t = localtime->new(blessed($t) && $t->isa('Time::Piece') ? $t->epoch : $t);
  my $entity = $self->entity;
  if ( $entity eq 'Account' ) {
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'AccountNote' ) {
    return {name => 'LastModifiedDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'AccountToDo' ) {
    return {name => 'LastModifiedDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'Contact' ) { # LOW: OR with LastModifiedDate
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'ContractNote' ) {
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'Opportunity' ) {
    return {name => 'LastActivity', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'Phase' ) {
    return {name => 'LastActivityDateTime', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'ProjectNote' ) {
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'Service' ) {
    return {name => 'LastModifiedDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'ServiceBundle' ) {
    return {name => 'LastModifiedDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'ServiceCall' ) {
    return {name => 'LastModifiedDateTime', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'Task' ) {
    return {name => 'LastActivityDateTime', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'TaskNote' ) {
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'Ticket' ) {
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'TicketNote' ) {
    return {name => 'LastActivityDate', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  } elsif ( $entity eq 'TimeEntry' ) {
    return {name => 'LastModifiedDateTime', expressions => [{op => 'GreaterThanOrEquals', value => $t->datetime}]};
  }
  return ();
}

sub _last_id {
  my $self = shift;
  my $last_id = $self->last_id;
  return {name => 'id', expressions => [{op => ($last_id ? 'GreaterThan' : 'GreaterThanOrEquals'), value => "$last_id"}]};
}

1;

sub _localtime {
  my $self = shift;
  my $now = $self->now;
  return blessed($now) && $now->isa('Time::Piece') ? $now : localtime;
}

sub _start_date {
  my $self = shift;
  return () unless my $t = $self->start_date;
  return () unless $t = localtime->new(blessed($t) && $t->isa('Time::Piece') ? $t->epoch : $t);
  my $entity = $self->entity;
  my %limits = (
    Account => 'CreateDate',
    AccountToDo => 'CreateDateTime',
    Appointment => 'CreateDateTime',
    BillingItem => 'ItemDate',
    Contact => 'CreateDate',
    ContractCost => 'CreateDate',
    ContractMilestone => 'CreateDate',
    ContractNote => 'LastActivityDate',
    Currency => 'LastModifiedDateTime',
    InstalledProduct => 'CreateDate',
    Invoice => 'CreateDateTime',
    Opportunity => 'CreateDate',
    Phase => 'CreateDate',
    Project => 'CreateDateTime',
    ProjectCost => 'CreateDate',
    ProjectNote => 'LastActivityDate',
    PurchaseOrder => 'CreateDateTime',
    Quote => 'CreateDate',
    QuoteTemplate => 'CreateDate',
    Service => 'CreateDate',
    ServiceBundle => 'CreateDate',
    ServiceCall => 'CreateDateTime',
    Task => 'CreateDateTime',
    TaskNote => 'LastActivityDate',
    Ticket => 'CreateDate',
    TicketCost => 'CreateDate',
    TicketNote => 'LastActivityDate',
    TimeEntry => 'CreateDateTime',
    UserDefinedFieldDefinition => 'CreateDate',
    UserDefinedFieldListItem => 'CreateDate',
  );
  return () unless my $name = $limits{$entity};
  my $now = $self->now || localtime;
  return (
    {name => $name, expressions => [{op => 'GreaterThanOrEquals', value => $t->strftime('%Y-%m-01T00:00:00')}]},
    {name => $name, expressions => [{op => 'LessThan', value => $now->add_months(1)->strftime('%Y-%m-01T00:00:00')}]},
  );
}

=encoding utf8

=head1 NAME 

Mojo::Autotask::Query - Build query filters for L<Mojo::Autotask>

=head1 SYNOPSIS

  package Mojo::Autotask;
  use Mojo::Base -base;

  use Mojo::Autotask::Query;

  has limits => sub { Mojo::Autotask::Query->new };

  package main;
  use Mojo::Base -strict;

  my $at = Mojo::Autotask->new;
  say $at->limits->Account(13)->Account;
  say $at->query(Account => [
    $at->limits->grep(AccountName => BeginsWith => 'S'),
    $at->limits->since(AccountName => BeginsWith => 'S'),
  ]);
=head1 DESCRIPTION


=head1 ATTRIBUTES

L<Mojo::Autotask::Query> implements the following attributes.

=head2 <Entity>

  my $months = $limits->$entity;
  $limits    = $limits->Ticket(24);

Some Autotask API entities support dates and these can be used to help narrow
the query results. L<Mojo::Autotask::Query> defines some good defaults for
how many months a query should be limited to. If the months is undefined then
the entity query is not limited by date.

The following Entities are defined as attributes with these defaults:

=over 4

=item Account => undef
=item AccountNote => 12
=item AccountToDo => 12
=item Appointment => 12
=item BillingItem => 12
=item Contact => undef
=item ContractCost => 48
=item ContractMilestone => 48
=item ContractNote => 48
=item Currency => undef
=item InstalledProduct => 12
=item Invoice => 12
=item Opportunity => 48
=item Phase => 24
=item Project => 24
=item ProjectCost => 24
=item ProjectNote => 24
=item PurchaseOrder => 48
=item Quote => 48
=item QuoteTemplate => undef
=item Service => undef
=item ServiceBundle => undef
=item ServiceCall => 12
=item Task => 12
=item TaskNote => 12
=item Ticket => 12
=item TicketCost => 12
=item TicketNote => 12
=item TimeEntry => 12
=item UserDefinedFieldDefinition => undef
=item UserDefinedFieldListItem => undef

=back

=head2 now

  $now    = $limits->now;
  $limits = $limits->now(Time::Piece->new);

Set the time basis for which the query should limit the date range for queries.

=head1 METHODS

=head2 clone

  $new_limits = $limits->clone($entity => $months);

Used by L<Mojo::Autotask/"query"> to temporarily override the date range in a
query.

=head2 grep

  @limit = $limits->grep([$name => $op => $value], ...);

Returns a limit data structure based on the provided criteria.

  @limit = $limits->grep([Account => Equals => 'Account Name'])
  @limit = $limits->grep(
    [Account => BeginsWith => 'A'],
    [Account => EndsWith   => 'E'],
  )

=head2 in_list

  @limit = $limits->in_list($name => $op => $value, $value, ...);

Returns a limit data structure looking for any of the specified values that
meet the $op condition of $name.

  @limit = $limits->in_list(Account => BeginsWith => 'A' .. 'E');

=head2 limit

  @limit = $limits->limit($entity)

Returns a limit data structure limiting the date range on the specified entity
by the number of months specified by the $entity attribute.

  @limit = $limits->limit('Account')

=head2 since

  @limit = $limits->since($entity => Time::Piece->new)

Returns a limit data structure limiting the date range on the specified entity
by returning only the items that have changed since the specified time.

=head1 DEPENDENCIES

L<Time::Piece>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Autotask>

=cut
