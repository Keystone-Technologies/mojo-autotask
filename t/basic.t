use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE=tid:u:p to enable this test' unless $ENV{TEST_ONLINE};

use Test::Mojo;

use Mojo::Autotask;
use Mojo::Util 'dumper';

use Role::Tiny;
use Time::Piece;

Role::Tiny->apply_roles_to_package('Time::Piece', 'Time::Piece::Role::More');

my ($tracking_id, $username, $password) = ($ENV{TEST_ONLINE} =~ /^(\w{27}):([^:]+):(.*?)$/);
diag "$tracking_id, $username, $password";
my $at = Mojo::Autotask->new(username => $username, password => $password, tracking_id => $tracking_id, max_records => 1_000);
diag ref $at->get_picklist_options(Account => 'KeyAccountIcon', 'Label');
diag $at->query('Account' => [], localtime->first_day_of_current_month)->size;
exit;
diag dumper $at->get_picklist_options(Account => 'KeyAccountIcon', 'Value');
diag dumper $at->get_picklist_options(Account => 'KeyAccountIcon', 'Label', 'T&M - 1');
diag dumper $at->get_picklist_options(Account => 'KeyAccountIcon', 'Value', 12);
exit;
diag $at->recache->query({Account => 2})->size;
#diag $at->query('Account')->size;
diag $at->get_threshold_and_usage_info->{EntityReturnInfoResults}->{EntityReturnInfo}->{Message};
diag $at->ec->open_ticket_detail(TicketNumber => 'T20181231.0001');

diag $at->recache->query(Account => [
  {
    name => 'AccountName',
    expressions => [{op => 'BeginsWith', value => 'b'}]
  },
])->size;

diag $at->recache->query('Account')->slice(0)->expand($at->cache,
  [qw/OwnerResourceID/],
  {
    InvoiceTemplateID => [
      qw/RateCostExpression/,
      OwnerResourceID => [$at->limits->grep([id => Equals => 30889315])]
    ]
  }
)->to_date->dump(0);
