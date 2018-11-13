package DataBase;

use DBI;
use XFileConfig;
use Digest::SHA qw(sha1_hex);

sub new{
  my ($class, %opts) = @_;
  my $self={ dbh=>undef, %opts };
  $self->{$_} ||= $c->{$_} for qw(db_name db_host db_login db_passwd);
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
  $self->{dbh}=DBI->connect("DBI:mysql:database=$self->{'db_name'};host=$self->{'db_host'};",$self->{'db_login'},$self->{'db_passwd'}) || die ("Can't connect to Mysql server.".$! );
  $dbh->{'mysql_enable_utf8'} = 1;
  $dbh->{'mysql_auto_reconnect'} = 1;
  $self->Exec("SET NAMES 'utf8'");
  $self->Exec("SET sql_mode = ''");
  $self->{'exec'}=0;
  $self->{'select'}=0;
}

sub InitMemd {
  require Cache::Memcached;
  my $self=shift;
  my @servers;
  push @servers, $c->{memcached_location};
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
  my $self = shift;
  my $sql = shift;

  if($c->{enable_query_log} && $sql =~ /$c->{enable_query_log}/)
  {
     require JSON;
     my ($pkg, $fn, $ln) = caller();

     open(DB_LOG, ">>logs/db.log");
     print DB_LOG (JSON->new->canonical(1)->encode({"_at" => "$fn:$ln", "_sql" => simplify($sql), params => \@_, "stacktrace" => stacktrace() }), "\n");
     close(DB_LOG);
  }

  $self->{dbh}->do($sql,undef,@_) || die"Can't exec:\n".$self->{dbh}->errstr;
  $self->{'exec'}++;
}

sub SelectOne
{
  my $self=shift;
  my $res = $self->{dbh}->selectrow_arrayref(shift,undef,@_);
  my ($pkg, $fn, $ln) = caller();
  die"Can't execute select at $fn:$ln:\n".$self->{dbh}->errstr if $self->{dbh}->err;
  $self->{'select'}++;
  return $res->[0];
};

sub SelectRow
{
  my $self=shift;
  my $res = $self->{dbh}->selectrow_hashref(shift,undef,@_);
  my ($pkg, $fn, $ln) = caller();
  die"Can't execute select at $fn:$ln:\n".$self->{dbh}->errstr if $self->{dbh}->err;
  $self->{'select'}++;
  return $res;
}

sub DoCached
{
  my ($self, $realm, $cb, $sql, @args) = @_;
  return $cb->($self, $sql, @args) if !$c->{memcached_location};

  my $key = sha1_hex(join(' ',$c->{dl_key}, $realm, @args), '');
  my $res = $self->{memd}->get($key);
  return($res) if($res);

  $res = $cb->($self, $sql, @args);
  $self->{memd}->set($key, $res, 3000);
  return($res);
}

sub Uncache
{
  my ($self, $realm, @args) = @_;
  return if !$c->{memcached_location};

  my $key = sha1_hex(join(' ',$c->{dl_key}, $realm, @args), '');
  $self->{memd}->delete($key);
}

sub SelectRowCached
{
   my ($self, $realm, $sql, @args) = @_;
   return $self->DoCached($realm, \&SelectRow, $sql, @args);
}

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

sub simplify
{
   my ($arg) = @_;
   $arg =~ s/\s+/ /g;
   return $arg;
}

sub stacktrace
{
   require File::Basename;
   my $i = 1;
   my ($pkg, $fn, $ln, @ret);
   push @ret, File::Basename::basename($fn) . ":$ln" while ($pkg, $fn, $ln) = caller($i++);
   return join("->", reverse(@ret));
}

1;
