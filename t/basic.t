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
#diag $at->max_records(500)->tap(sub{shift->limits->Account(3)})->cache->query('Account')->size;
#diag $at->query('Account')->size;
#diag $at->max_records(500)->query('Account')->size;
#diag $at->get_threshold_and_usage_info->{EntityReturnInfoResults}->{EntityReturnInfo}->{Message};
#diag $at->ec->open_ticket_detail(TicketNumber => 'T20181231.0001');
#diag dumper $at->get_field_info_c('Ticket', 'AccountID');
#diag time;
#my $cache = $at->cache_c->expires(86_400);
#diag $cache->query(Account => [
#  {
#    name => 'AccountName',
#    expressions => [{op => 'BeginsWith', value => 'b'}]
#  },
#])->size;
#diag $cache->query('Account')->size;
#diag dumper $cache->query('Account')->first;
#diag time;
#diag $cache->get_udf_info('Account')->size;
#diag dumper $cache->query('Account')->slice(0)->expand($at, {OwnerResourceID => [qw/FirstName LastName/]})->first;
#diag dumper $cache->query('Account')->slice(0)->expand($at, {OwnerResourceID => [qw/FirstName LastName/, $at->limits->grep([id => Equals => 30889381])]})->size;
