use Mojo::Base -strict;

use Test::More;

use Mojo::Autotask;
use Mojo::Autotask::Query;
use Mojo::Autotask::Util qw(grep in_list localtime);
use Mojo::Util 'dumper';

my $at = Mojo::Autotask->new;
is $at->soap_proxy->to_string, 'https://webservices5.autotask.net/ATServices/1.6/atws.asmx';
$at->query_p(Ticket => [grep([TicketNumber => Equals => 'T20190101.0001'])])->then(sub {
  diag shift->size;
})->wait;
my $query = {entity => 'Ticket', query => [grep([TicketNumber => Equals => 'T20190101.0001'])]};
$at->query_p($query)->then(sub {
  diag shift->size;
})->wait;
$at->query_p({entity => 'Ticket', query => [grep([TicketNumber => Equals => 'T20190101.0001'])]})->then(sub {
  diag shift->size;
})->wait;
$query = Mojo::Autotask::Query->new(entity => 'Ticket', start_date => localtime->add_months(-3));
diag dumper(@$query);
$at->query_all_p($query)->then(sub {
  diag dumper($_[0]->first);
  diag dumper(shift->grep(sub{$_->{Source} && $_->{Source} == 4})->size);
})->wait;
#diag dumper($at->entities);
#diag dumper($at->entities->{Ticket});
#$at->get_field_info_p('Ticket')->then(sub {
#  diag dumper(shift);
#})->wait;
$at->get_zone_info_p->then(sub {
  is shift->{WebUrl}, "https://ww5.autotask.net/";
})->wait;
$at->get_threshold_and_usage_info_p->then(sub {
  like shift->{Message}, qr(ThresholdOfExternalRequest);
})->wait;
$at->get_entity_info_p->then(sub {
  ok shift->[0]->{Name};
})->wait;
$at->get_field_info_p('Ticket')->then(sub {
  ok shift->[0]->{Name};
})->wait;
$at->get_udf_info_p('Ticket')->then(sub {
  ok shift->[0]->{Name};
})->wait;
is $at->ec->open_ticket_detail(TicketNumber => 'T20190101.0001')->query->param('Code'), 'OpenTicketDetail';

done_testing;
