package Mojolicious::Plugin::Autotask;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Autotask;
use Mojo::Recache;

sub register {
  my ($self, $app, $conf) = @_;

  push @{$app->commands->namespaces}, 'Mojo::Autotask::Command';
  my $cache = Mojo::Recache->new(home => $app->home, log => $app->log);
  my $at = Mojo::Autotask->new(%$conf, cache => $cache);
  $at->cache->app($app);
  $app->helper('autotask' => sub {$at});
}

1;
__END__

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Autotask - Mojolicious Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Autotask');

  # Mojolicious::Lite
  plugin 'Autotask';

=head1 DESCRIPTION

L<Mojolicious::Plugin::Autotask> is a L<Mojolicious> plugin.

=head1 METHODS

L<Mojolicious::Plugin::Autotask> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
