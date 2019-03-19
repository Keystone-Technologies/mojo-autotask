use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set MOJO_AUTOTASK_USERNAME, MOJO_AUTOTASK_PASSWORD, and MOJO_AUTOTASK_TRACKINGID to run these tests'
  unless $ENV{AUTOTASK_USERNAME} && $ENV{AUTOTASK_PASSWORD} && $ENV{AUTOTASK_TRACKINGID};

use Mojo::Autotask;
use Mojo::Autotask::Query;
use Mojo::Autotask::Util qw(filter in_list localtime);
use Mojo::Util 'dumper';

my $at = Mojo::Autotask->new;
say $at->query_all('Ticket')->expand($at)->size;
done_testing; exit;

#say $at->query('AccountAlert')->expand($at, {AccountID => ['AccountName']})->grep(sub{$_->{AccountID_ref_AccountName}})->dump;
#my $res = $at->query_all('AccountAlert')->expand($at, {AccountID => ['AccountName']})->grep(sub{$_->{AccountID_ref_AccountName}});
#say $res->each(sub{$_->{AlertText}=~tr/A-Z/a-z/})->dump(0..2);
#say $res->dump(0..2);
#say $res->collapse->dump(0..2);
#say dumper($at->update(shift->slice(0..2)));

is $at->soap_proxy->to_string, 'https://webservices5.autotask.net/ATServices/1.6/atws.asmx', 'right soap proxy';
ok scalar keys %{$at->entities} > 10, 'got plenty of entities';
is $at->get_zone_info->{WebUrl}, 'https://ww5.autotask.net/', 'right weburl';
$at->get_zone_info_p->then(sub {
  is shift->{WebUrl}, 'https://ww5.autotask.net/', 'right weburl';
})->wait;
$at->get_threshold_and_usage_info_p->then(sub {
  like shift->{Message}, qr(ThresholdOfExternalRequest), 'got threshold info';
})->wait;
$at->get_entity_info_p->then(sub {
  ok shift->[0]->{Name}, 'got entity name';
})->wait;
$at->get_field_info_p('Ticket')->then(sub {
  ok shift->[0]->{Name}, 'got field name';
})->wait;
$at->get_udf_info_p('Ticket')->then(sub {
  ok shift->[0]->{Name}, 'got udf name';
})->wait;
is $at->ec->open_ticket_detail(TicketNumber => 'T20190101.0001')->query->param('Code'), 'OpenTicketDetail', 'right ec url';

$at->query_p(Ticket => [filter([TicketNumber => Equals => 'T20190101.0001'])])->then(sub {
  ok shift->size, 'got ticket';
})->wait;
my $query = {entity => 'Ticket', query => [filter([TicketNumber => Equals => 'T20190101.0001'])]};
$at->query_p($query)->then(sub {
  ok shift->size, 'got ticket';
})->wait;
$at->query_p({entity => 'Ticket', query => [filter([TicketNumber => Equals => 'T20190101.0001'])]})->then(sub {
  ok shift->size, 'got ticket';
})->wait;
my $res = $at->query({entity => 'Ticket', query => [filter([TicketNumber => Equals => 'T20190101.0001'])]});
ok $res->size, 'got ticket';

$query = Mojo::Autotask::Query->new(at => $at, entity => 'Ticket', start_date => localtime->add_months(-3));
$at->query_all_p($query)->then(sub {
  my $res = shift;
  ok $res->size > 500, 'more than 500 records';
  ok $res->first->{Status}, 'a ticket has a status';
  ok $res->grep(sub{$_->{Source} && $_->{Source} == 4})->size > 1, 'more than 1 of this source';
})->wait;

done_testing;
