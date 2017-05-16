package DataBase;

use DBI;
use XFileConfig;
use Digest::SHA qw(sha1_hex);

sub new{
  my $class=shift;
  my $self={ dbh=>undef };
  bless $self,$class;
  $self->InitDB;
  $self->InitMemd if $c->{memcached_location};
  return $self;
}

sub inherit{
  my $class = shift;
  my $dbh   = shift;
  my $self={ dbh=>undef };
  bless $self,$class;
  $self->{dbh} = $dbh;
  return $self;
}


sub dbh{shift->{dbh}}

sub InitDB{
  my $self=shift;
  $self->{dbh}=DBI->connect("DBI:mysql:database=$c->{'db_name'};host=$c->{'db_host'};",$c->{'db_login'},$c->{'db_passwd'}) || die ("Can't connect to Mysql server.".$! );
  $dbh->{'mysql_enable_utf8'} = 1;
  $self->Exec("SET NAMES 'utf8'");
  $self->{'exec'}=0;
  $self->{'select'}=0;
}

sub InitMemd {
  my $self=shift;
  my @servers;
  push @servers, $c->{memcached_location} if eval {require Cache::Memcached; }||!$@;
  $self->{memd} = new Cache::Memcached { 'servers' => \@servers };
}

sub DESTROY{
  shift->UnInitDB();
}

sub UnInitDB{
  my $self=shift;
  if($self->{dbh})
  {
    if($self->{locks})
    {
          $self->Unlock();
    }
    $self->{dbh}->disconnect;
  }
  $self->{dbh}=undef;
}

sub Exec
{
  my $self=shift;
  $self->{dbh}->do(shift,undef,@_) || die"Can't exec:\n".$self->{dbh}->errstr;
  $self->{'exec'}++;
}

sub SelectOne
{
  my $self=shift;
  my $res = $self->{dbh}->selectrow_arrayref(shift,undef,@_);
  die"Can't execute select:\n".$self->{dbh}->errstr if $self->{dbh}->err;
  $self->{'select'}++;
  return $res->[0];
};

sub SelectRow
{
  my $self=shift;
  my $res = $self->{dbh}->selectrow_hashref(shift,undef,@_);
  die"Can't execute select:\n".$self->{dbh}->errstr if $self->{dbh}->err;
  $self->{'select'}++;
  return $res;
}

sub DoCached
{
  my ($self, $realm, $cb, @args) = @_;
  return $cb->($self, @args) if !$c->{memcached_location};

  my $key = sha1_hex(join(' ',$c->{dl_key}, $realm, @args), '');
  my $res = $self->{memd}->get($key);
  return($res) if($res);

  $res = $cb->($self, @args);
  $self->{memd}->set($key, $res, 3000);
  return($res);
}

sub SelectRowCached { shift->DoCached('SelectRow', \&SelectRow, @_) }

sub Select
{
  my $self=shift;

  my $res = $self->{dbh}->selectall_arrayref( shift, { Slice=>{} }, @_ );
  die"Can't execute select:\n".$self->{dbh}->errstr if $self->{dbh}->err;
  return undef if $#$res==-1;
  my $cidxor=0;
  for(@$res)
  {
    $cidxor = $cidxor ^ 1;
    $_->{row_cid} = $cidxor;
  }
  $self->{'select'}++;
  return $res;
}

sub SelectARef
{
   my $self = shift;
   my $data = $self->Select(@_);
   return [] unless $data;
   return [$data] unless ref($data) eq 'ARRAY';
   return $data;
}

sub getLastInsertId
{
  return shift->{ dbh }->{'mysql_insertid'};
}


1;                                                           
