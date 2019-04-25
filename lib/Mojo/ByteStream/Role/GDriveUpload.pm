package Mojo::ByteStream::Role::GDriveUpload;
use Mojo::Base -role;

use Mojo::File 'path';
use Mojo::JSON 'j';
use Mojo::UserAgent;
use Mojo::Util 'md5_sum';

sub upload {
  my ($self, %config) = @_;
  return $self if $ENV{NO_GDRIVEUPLOAD};
  my $parents = $config{parents};
  my $auth = $config{auth};
  my ($GDRIVE_CLIENT_ID, $GDRIVE_CLIENT_SECRET, $GDRIVE_REFRESH_TOKEN) = map { $auth->{$_} || $ENV{$_} } qw/GDRIVE_CLIENT_ID GDRIVE_CLIENT_SECRET GDRIVE_REFRESH_TOKEN/;
  return $self unless $GDRIVE_CLIENT_ID && $GDRIVE_CLIENT_SECRET && $GDRIVE_REFRESH_TOKEN;

  my $content = "$self";
  $content =~ s/[^\x00-\x7f]//g;
  my $name = sprintf '%s-%s.csv', path($0)->tap(sub{$_ = $_->basename;s/\..*?$//;$_}), md5_sum(localtime.$$);
  warn length($content);

  my $ua = Mojo::UserAgent->new;
  my $access_token = $ua->post('https://www.googleapis.com/oauth2/v4/token' => form => {
    client_id     => $GDRIVE_CLIENT_ID,
    client_secret => $GDRIVE_CLIENT_SECRET,
    refresh_token => $GDRIVE_REFRESH_TOKEN,
    grant_type => 'refresh_token'
  })->result->json('/access_token');
  warn $access_token;
  my $json = $ua->post('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart' => {Authorization => "Bearer $access_token"} => multipart => [
    {
      content            => j({name => $name, parents => $parents}),
      'Content-Type'     => 'application/json;charset=UTF-8',
    },
    {
      content            => $content,
      'Content-Type'     => 'text/csv',
    }
  ])->result->json if $access_token;
  my $url = sprintf 'https://drive.google.com/open?id=%s', $json->{id};
  warn "$name: $url";
  $ENV{GDRIVE_URL} = $url;
  $ENV{GDRIVE_NAME} = $name;
  return $self;
}

1;
