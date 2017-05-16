package XUtils;
use strict;
use XFileConfig;

sub ReportFile
{
   # Adds the file in abuses list
   # %opts: usr_id - reporter's ID
   #        ban - ban file by (file_md5, file_size)
   my ($ses, $file, %opts) = @_;
   my $db = $ses->db;
   my $reporter = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $opts{usr_id}) if $opts{usr_id};
   $reporter ||= { usr_id => 0, usr_login => $opts{usr_login}, usr_email => $opts{usr_email} } if $opts{usr_login};
   my $ban = ",ban_size='$file->{file_size}', ban_md5='$file->{file_md5}' " if $ses->getUser->{takedown_md5};
   $db->Exec("INSERT INTO Reports SET file_id=?,
         usr_id=?,
         filename=?,
         name=?,
         email=?,
         info='auto',
         created=NOW() $ban",
         $file->{file_id},
         $file->{usr_id},
         $file->{file_name},
         $reporter->{usr_login},
         $reporter->{usr_email},
         );
}

sub RunServerTests
{
   my ($ses, $srv_id) = @_;
   my $db = $ses->db;
   my $server = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?", $srv_id);

   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new( timeout => 15, agent => 'Opera/9.51 (Windows NT 5.1; U; en)' );

   my @tests;
   # api.cgi multiple tests
   my $res = $ses->api2( $srv_id, { op => 'test', site_cgi => $c->{site_cgi} } );
   if ( $res =~ /^OK/ )
	{
      push @tests, 'api.cgi: OK';
      $res =~ s/^OK:(.*?)://;
      push @tests, split( /\|/, $res );
   }
	else
	{
      push @tests, "api.cgi: ERROR ($res)";
   }

   # upload.cgi
   $res = $ua->get("$server->{srv_cgi_url}/upload.cgi?mode=test");
   push @tests, $res->content eq 'XFS' ? 'upload.cgi: OK' : "upload.cgi: ERROR (problems with <a href='$server->{srv_cgi_url}/upload.cgi\?mode=test' target=_blank>link</a>)";

   # htdocs URL accessibility
   $res = $ua->get("$server->{srv_htdocs_url}/index.html");
   push @tests, $res->content eq 'XFS' ? 'htdocs URL accessibility: OK' : "htdocs URL accessibility: ERROR (should see XFS on <a href='$server->{srv_htdocs_url}/index.html' target=_blank>link</a>)";
   return(@tests);

}

sub Ban
{
   # Purpose: ban user and/or IP
   my ($ses, %opts) = @_;
   if($opts{usr_id})
	{
      # Also ban user in XFileSharing <= 2.0 way
      $ses->db->Exec("UPDATE Users SET usr_status='BANNED' WHERE usr_id=?", $opts{usr_id});
   }
   $ses->db->Exec("INSERT IGNORE INTO Bans SET usr_id=?,
               ip=INET_ATON(?),
               reason=?",
         $opts{usr_id}||0,
         $opts{ip}||0,
         $opts{reason}||'',
         );
}

sub genDirectLink
{
   my ($file,%rest)=@_;
   $rest{usr_id} ||= 0;
   $rest{ip} ||= $ENV{REMOTE_ADDR};
   $rest{fname}||=$file->{file_name};
   require HCE_MD5;
   my $hce = HCE_MD5->new($c->{dl_key},"XFileSharingPRO");
   my $usr_id = 0;
   my $dx = sprintf("%d",($file->{file_real_id}||$file->{file_id})/$c->{files_per_folder});
   my $hash = &encode32( $hce->hce_block_encrypt(pack("SLLSA12ASC4L",
                                                       $file->{srv_id},
                                                       $file->{file_id},
                                                       $rest{usr_id},
                                                       $dx,
                                                       $file->{file_real},
                                                       $rest{mode}||'f',
                                                       $c->{down_speed},
                                                       split(/\./,$rest{ip}),
                                                       time+60*$rest{mins})) );
   #$file->{file_name}=~s/%/%25/g;
   #$file->{srv_htdocs_url}=~s/\/files//;
   my ($url) = $file->{srv_htdocs_url}=~/(http:\/\/.+?)\//i;
   return "$url:182/d/$hash/$rest{fname}";
}

sub encode32
{         
    $_=shift;
    my($l,$e);
    $_=unpack('B*',$_);
    s/(.....)/000$1/g;
    $l=length;
    if($l & 7)
    {
       $e=substr($_,$l & ~7);
       $_=substr($_,0,$l & ~7);
       $_.="000$e" . '0' x (5-length $e);
    }
    $_=pack('B*', $_);
    tr|\0-\37|A-Z2-7|;
    lc($_);
}

sub CreateTransaction
{
   # Purpose: create a new payment transaction
   # Returns: new transaction id
   my ($ses, %opts) = @_;
   my $db = $ses->db;
   my $id = int( 1 + rand 9 ) . join( '', map { int( rand 10 ) } 1 .. 9 );
   $db->Exec("INSERT INTO Transactions SET id=?, usr_id=?, amount=?, ip=INET_ATON(?), created=NOW(), aff_id=?, ref_url=?, verified=?, origin=?",
         $id,
         $opts{usr_id},
         $opts{amount},
         $ses->getIP||'0.0.0.0',
         $opts{aff_id}||0,
         $opts{ref_url}||'',
         $opts{verified}||0,
         $opts{origin}||'',
         );
   return($id);
}

sub chargeRef
{
   # Purpose: add $amount to $usr_id and run the necessary hooks
   # Returns: amount charged
   my ($ses, $usr_id, $amount, %opts) = @_;
   my $db = $ses->db;
   $opts{type} ||= 'seller';
   die("Unknown referral type: $opts{type}")
      if $opts{type} !~ /^(seller|referral|webmaster)/;

   $ses->AdminLog("Charging $amount to $opts{type} $usr_id");
   $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $amount, $usr_id) if $usr_id && $amount;

   # Updating stats
   my $f_count = {   seller => 'sales',
      }->{$opts{type}};
   my $f_amount = {   seller => 'profit_sales',
         referral => 'profit_refs',
         webmaster => 'profit_site',
      }->{$opts{type}};
   if($f_count)
	{
      $db->Exec("INSERT INTO Stats2
                      SET usr_id=?, day=CURDATE(), $f_count=1
            ON DUPLICATE KEY UPDATE $f_count=$f_count+1", $usr_id);
   }
   $db->Exec("INSERT INTO Stats2
                      SET usr_id=?, day=CURDATE(), $f_amount=$amount
                      ON DUPLICATE KEY UPDATE $f_amount=$f_amount+$amount",$usr_id) if $c->{m_s} && $usr_id;
   return($amount);
}

sub TestFile
{
   my ($db, $file_code) = @_;
   my $file = $db->SelectRow("SELECT *, INET_NTOA(file_ip) as file_ip, u.usr_profit_mode, s.srv_htdocs_url
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id 
                              WHERE f.file_code=? 
                              AND f.srv_id=s.srv_id",$file_code);
   return undef if !$file;
   my $direct_link = &genDirectLink($file, ip => '1.1.1.1');
   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new( timeout => 1, agent => 'Opera/9.51 (Windows NT 5.1; U; en)' );
   my $res = $ua->head($direct_link);
   return $res->code;
}

sub CheckAuth
{
  my ($ses, $sess_id) = @_;
  my $sess_id = $ses->getCookie( $ses->{auth_cook} );
  my $db= $ses->db;
  my $f= $ses->f;
  return undef unless $sess_id;
  $ses->{user} = $db->SelectRow("SELECT u.*,
                                        UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec,
                                        UNIX_TIMESTAMP()-UNIX_TIMESTAMP(last_time) as dtt
                                 FROM Users u, Sessions s 
                                 WHERE s.session_id=? 
                                 AND s.usr_id=u.usr_id",$sess_id);
  unless($ses->{user})
  {
     return undef;
  }
  if ( $ses->{user}->{usr_adm} && ( my $mangle_id = $ses->getCookie('mangle_id') ) )
  {
     $ses->{user} = $db->SelectRow(
           "SELECT *,
           UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
           FROM Users
           WHERE usr_id=?", $mangle_id
           );
     $ses->{lang}->{mangle} = 1;
  }
  if($ses->{user}->{usr_status} eq 'BANNED')
  {
     delete $ses->{user};
     $ses->message("Your account was banned by administrator.");
  }
  if($ses->{user}->{dtt}>30)
  {
     $db->Exec("UPDATE Sessions SET last_time=NOW() WHERE session_id=?",$sess_id);
     $db->Exec("UPDATE Users SET usr_lastlogin=NOW(), usr_lastip=INET_ATON(?) WHERE usr_id=?", $ses->getIP, $ses->{user}->{usr_id} );
  }
  $ses->{user}->{premium}=1 if $ses->{user}->{exp_sec}>0;
  if($c->{m_d} && $ses->{user}->{usr_mod})
  {
      $ses->{lang}->{usr_mod}=1;
      $ses->{lang}->{m_d_f}=$c->{m_d_f};
      $ses->{lang}->{m_d_a}=$c->{m_d_a};
      $ses->{lang}->{m_d_c}=$c->{m_d_c};
  }

  $ses->{lang}->{enable_reports} = $c->{enable_reports};

  #$ses->setCookie( $ses->{auth_cook} , $sess_id );
  return $ses->{user};
}

sub CheckLoginPass
{
   use MIME::Base64;
   use PBKDF2::Tiny;

   my ($ses, $login, $pass) = @_;

   my $user = $ses->db->SelectRow("SELECT * FROM Users WHERE usr_login=?  AND !usr_social", $login);

   my $answer = $user->{usr_password} =~ /^sha256:/
      ? _check_password_pbkdf2($pass, $user->{usr_password})
      : _check_password_legacy($pass, $ses->db, $user->{usr_id});

   return GetUser($ses, $user->{usr_id}) if $answer;
   return 0;
}

sub _check_password_pbkdf2
{
   my ($actual_pass, $hashed_pass) = @_;
   my ($algo, $turns, $salt, $data) = split(/:/, $hashed_pass);
   return PBKDF2::Tiny::verify( decode_base64($data), 'SHA-256', $actual_pass, decode_base64($salt), $turns );
}

sub _check_password_legacy
{
   my ($actual_pass, $db, $usr_id) = @_;
   return $db->SelectOne("SELECT usr_id FROM Users
      WHERE usr_id=?
      AND usr_password=ENCODE(?, ?)",
      $usr_id,
      $actual_pass,
      $c->{pasword_salt});
}

sub GetUser
{
   my ($ses, $usr_id) = @_;
   my $user = $ses->db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
         FROM Users 
         WHERE usr_id=?", $usr_id );
   if($user && $user->{usr_status} eq 'BANNED')
   {
      delete $ses->{user};
      return $ses->message("Your account was banned by administrator.");
   }

   $user->{utype} = $user ? ($user->{exp_sec} > 0 ? 'prem' : 'reg') : 'anon' if $user;

   return $user;
}

sub SelectServer
{
   my $ses = shift;
   my $user = shift;

   my @custom_filters = map { " AND $_"} @_;
   my $type_filter = $user && $user->{utype} eq 'prem' ? "AND srv_allow_premium=1" : "AND srv_allow_regular=1";
   my $country_filter;

   if($c->{m_g} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      my $country = $gi->country_code_by_addr($ses->getIP);
      $country_filter="AND (srv_countries LIKE '%$country%' OR srv_countries='')" if $country;
      $country_filter||="AND srv_countries=''";
   }

   my $server = $ses->db->SelectRow("SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max*0.99
                                $type_filter
                                $country_filter
                                @custom_filters
                                ORDER BY RAND()
                                LIMIT 1",$c->{max_upload_filesize}||100);
   if($c->{m_g} && !$server)
   {
      $server = $ses->db->SelectRow("SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max*0.98
                                $type_filter
                                @custom_filters
                                ORDER BY RAND()
                                LIMIT 1",$c->{max_upload_filesize}||100);
   }

   return $server;
}

sub GenPasswdHash
{
   require PBKDF2::Tiny;
   require MIME::Base64;

   my ($pass) = @_;
   my $turns = 1000;
   my $salt = join('', map { chr( rand(256) ) } (1..24));
   my $data = PBKDF2::Tiny::derive('SHA-256', $pass, $salt, $turns);
   my $hash = sprintf("sha256:%d:%s:%s",
      $turns,
      MIME::Base64::encode_base64($salt, ''),
      MIME::Base64::encode_base64($data, ''));

   return $hash;
}

1;
