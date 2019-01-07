use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Test',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Test.pm',
  AUTHOR       => 'A Good Programmer <nospam@cpan.org>',
  PREREQ_PM    => {'Mojolicious' => '7.92'},
  test         => {TESTS => 't/*.t'}
);
