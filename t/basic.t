use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Test::Mojo;

use Mojo::Autotask;
use Mojo::Util 'dumper';

my ($username, $password) = ($ENV{TEST_ONLINE} =~ /^([^:]+):(.*?)$/);
my $at = Mojo::Autotask->new(username => $username, password => $password);
warn $at->get_threshold_and_usage_info->{EntityReturnInfoResults}->{EntityReturnInfo}->{Message};
warn $at->ec->open_ticket_detail(TicketNumber => 'T20181231.0001');
warn dumper $at->get_field_info_c('Ticket', 'AccountID');
warn time;
my $cache = $at->cache_c->expires(86_400);
warn $cache->query(Account => [
  {
    name => 'AccountName',
    expressions => [{op => 'BeginsWith', value => 'b'}]
  },
])->size;
warn $cache->query('Account')->size;
warn time;
