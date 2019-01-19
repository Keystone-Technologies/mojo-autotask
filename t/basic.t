use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Test::Mojo;

use Mojo::Autotask;
use Mojo::Util 'dumper';

my ($tracking_id, $username, $password) = ($ENV{TEST_ONLINE} =~ /^(\w{27}):([^:]+):(.*?)$/);
diag "$tracking_id, $username, $password";
my $at = Mojo::Autotask->new(username => $username, password => $password, tracking_id => $tracking_id, max_records => 1_000);

diag $at->cache->query({Account => 2})->size;
#diag $at->query('Account')->size;
diag $at->get_threshold_and_usage_info->{EntityReturnInfoResults}->{EntityReturnInfo}->{Message};
diag $at->ec->open_ticket_detail(TicketNumber => 'T20181231.0001');

diag $at->cache->query(Account => [
  {
    name => 'AccountName',
    expressions => [{op => 'BeginsWith', value => 'b'}]
  },
])->size;

diag $at->cache->query('Account')->slice(0)->expand($at->cache, [qw/OwnerResourceID CountryID/], {InvoiceTemplateID => [qw/RateCostExpression/], OwnerResourceID => [$at->limits->grep([id => Equals => 30889315])]})->to_date->dump(0);
