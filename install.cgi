#!/usr/bin/perl
use strict;
use lib '.';
use XFileConfig;

BEGIN
{
   my $ok = "<b style='background:#1a1;color:#fff;padding:2px;'>OK</b>";
   my $err = "<b>Fail</b>";

   my @modules =
   (                                                   
       {module=>'CGI', file=>'CGI.pm', redhat=>'perl-CGI', debian=>'libcgi-pm-perl'}, 
       {module=>'DBI', file=>'DBI.pm', redhat=>'perl-DBI', debian=>'libdbi-perl'}, 
       {module=>'DBD::mysql', file=>'DBD/mysql.pm', redhat=>'perl-DBD-MySQL', debian=>'libdbd-mysql-perl'}, 
       {module=>'Digest::SHA', file=>'Digest/SHA.pm', redhat=>'perl-Digest-SHA', debian=>'libdigest-sha-perl'},
       {module=>'LWP', file=>'LWP/UserAgent.pm', redhat=>'perl-libwww-perl', debian=>'libwww-perl'},
       {module=>'Crypt::SSLeay', file=>'Crypt/SSLeay.pm', redhat=>'perl-Crypt-SSLeay', debian=>'libcrypt-ssleay-perl'},
       {module=>'LWP::Protocol::https', file=>'LWP/Protocol/https.pm', redhat=>'perl-LWP-Protocol-https', debian=>'liblwp-protocol-https-perl'},
       {module=>'Time::HiRes', file=>'Time/HiRes.pm', redhat=>'perl-Time-HiRes', debian=>''},
   );

   my @failed_modules = grep { ! eval { require $_->{file} } && $@ } @modules;
   my %is_failed = map { $_->{module} => 1 } @failed_modules;

   if(@failed_modules)
   {
      my @redhat_pkgs = map { $_->{redhat} } @failed_modules if -e '/usr/bin/yum';
      my @debian_pkgs = map { $_->{debian} } @failed_modules if -e '/usr/bin/apt-get';

      print "Content-type: text/html\n\n";
      print "Testing modules...<br><br>\n";
      print "<table style='width: 320px'>\n";

      for(@modules)
      {
         my $status = $is_failed{ $_->{module} } ? $err : $ok;
         print "<tr><td><b>$_->{module}...</b></td><td>$status</td></tr>\n";
      }

      print "</table><br><br>\n";

      print "It looks like there are some Perl modules are missing.<br>\n";
      print "You can install all of them at once by issuing the following command from root SSH console:<br><br>\n" if @redhat_pkgs || @debian_pkgs;
      printf ("<font style='font-family: monospace'>yum install %s</font>", join(' ', @redhat_pkgs)) if @redhat_pkgs;
      printf ("<font style='font-family: monospace'>apt-get install %s</font>", join(' ', @debian_pkgs)) if @debian_pkgs;

      exit();
   }
};

use Session;
use XUtils;
use CGI::Carp qw(fatalsToBrowser);
use DBI;

my $ok = "<br><b style='background:#1a1;color:#fff;padding:2px;'>OK</b>";

my $ses = Session->new;
my $f = $ses->f;

sub add_cronjob {
   my ($spec) = @_;

   local *getCmd = sub {
      my @chunks = split(/\s+/, $_[0], 6);
      return $chunks[5];
   };

   my $crontext_old = `crontab -l`;
   my $existing = grep { getCmd($spec) eq getCmd($_) } split(/\n/, $crontext_old);
   return if $existing;

   open(CRONTAB, "| crontab -");
   print CRONTAB $crontext_old;
   print CRONTAB "$spec\n";
   close(CRONTAB);
}

if($f->{site_settings})
{
   my @fields = qw(temp_dir upload_dir cgi_dir htdocs_dir htdocs_tmp_dir);
   $f->{temp_dir}   = "$f->{cgi_path}/temp";
   $f->{upload_dir} = "$f->{cgi_path}/uploads";
   $f->{htdocs_dir} = "$f->{site_path}/files";
   $f->{htdocs_tmp_dir} = "$f->{site_path}/tmp";
   $f->{cgi_dir} = $f->{cgi_path};
   mkdir("$f->{cgi_dir}/logs");
   my $conf;
   open(F,"XFSConfig.pm")||$ses->message("Can't read XFSConfig");
   $conf.=$_ while <F>;
   close F;
   for my $x (@fields)
   {
      my $val = $f->{$x};
      $conf=~s/$x\s*=>\s*(\S+)\s*,/"$x => '$val',"/e;
   }
   open(F,">XFSConfig.pm")||$ses->message("Can't write XFSConfig");
   print F $conf;
   close F;

   add_cronjob("*/1 * * * *\tcd $f->{cgi_dir} && ./transfer.pl 2>&1 >/dev/null") if $f->{cgi_dir};
}

if($f->{save_sql_settings} || $f->{site_settings})
{
   my @fields = $f->{save_sql_settings} ? qw(db_host db_login db_passwd db_name pasword_salt dl_key) : qw(site_url site_cgi site_path cgi_path license_key);
   my $conf;
   $f->{$_}=~s/\s+$//g for @fields;
   $f->{$_}=~s/^\s+//g for @fields;
   open(F,"XFileConfig.pm")||$ses->message("Can't read XFileConfig");
   $conf.=$_ while <F>;
   close F;
   $f->{pasword_salt} = $c->{pasword_salt}||$ses->randchar(12);
   $f->{dl_key}       = $c->{dl_key}||$ses->randchar(10);
   for my $x (@fields)
   {
      my $val = $f->{$x};
      $conf=~s/$x\s*=>\s*.+?\s*,/"$x => '$val',"/e;
   }
   open(F,">XFileConfig.pm")||$ses->message("Can't write XFileConfig");
   print F $conf;
   close F;

   if($f->{cgi_path})
   {
      add_cronjob("*/10 * * * *\tcd $f->{cgi_path} && ./cron.pl 2>&1 >/dev/null");
      add_cronjob("0 23 * * *\tcd $f->{cgi_path} && ./cron_deleted_email.pl 2>&1 >/dev/null");
   }

   $ses->redirect('install.cgi');
}

if($f->{create_sql})
{
   my $db = $ses->db;
   open(FILE,"install.sql")||$ses->message("Can't open install.sql: $!");
   my $sql;
   $sql.=$_ while <FILE>;
   $sql=~s/CREATE TABLE/CREATE TABLE IF NOT EXISTS/gis;
   $db->Exec($_) for grep{length($_)>17} split(';',$sql);
   
   my $passwd_hash = XUtils::GenPasswdHash($f->{usr_password});

   $db->Exec("INSERT INTO Users (usr_login,usr_email,usr_password,usr_created,usr_adm) VALUES (?,?,?,NOW(),1)",$f->{usr_login},$f->{usr_email},$passwd_hash);
   $db->Exec("INSERT INTO Misc SET name='last_notify_time', value=UNIX_TIMESTAMP()");
   $ses->redirect('install.cgi');
}

if($f->{remove_install})
{
   print"Content-type:text/html\n\n";
   unlink('install.cgi');
   print"Can't delete <u>install.cgi</u>, remove it manually<br><br>" if -e 'install.cgi';
   unlink('install.sql');
   print"Can't delete <u>install.sql</u>, remove it manually<br><br>" if -e 'install.sql';
   unlink('upgrade_25_251.cgi');
   print"Can't delete <u>upgrade_25_251.cgi</u>, remove it manually<br><br>" if -e 'upgrade_25_251.cgi';
   unlink('upgrade_25_251.sql');
   print"Can't delete <u>upgrade_25_251.sql</u>, remove it manually<br><br>" if -e 'upgrade_25_251.sql';
   print qq[<br><input type='button' value='Go to Login page' onClick="window.location='$c->{site_url}/?op=login&redirect=$c->{site_url}';">];

   my $subdir = $1 if $ENV{REQUEST_URI} =~ /^(.*)\/cgi-bin\/install.cgi/;
   if($subdir)
   {
      my $htaccess;
      open(FILE, "$c->{site_path}/.htaccess");
      $htaccess .= $_ while <FILE>;
      close FILE;

      $htaccess =~ s/\/cgi-bin/$subdir\/cgi-bin/;

      open(FILE, ">$c->{site_path}/.htaccess");
      print FILE $htaccess;
      close FILE;

      print "<br>Installed in subdirectory: $subdir/\n";
   }

   exit;
}

#######

print"Content-type:text/html\n\n";
print"<HTML><BODY style='font:13px Arial;'><h2>XFileSharingPro Installation Script</h2>";

############
print"<hr>";
############

print"<b>1) Permissions Check</b><br><br>";
my $perms = {
               'logs.txt'     => 0666,
               'ipn_log.txt'     => 0666,
               'fs.cgi'       => 0755,
               'index.cgi'    => 0755,
               'index_box.cgi'   => 0755,
               'index_dl.cgi'    => 0755,
               'ipn.cgi'    => 0755,
               'cron.pl'      => 0755,
               'cron_deleted_email.pl' => 0755,
               'dl.cgi'      => 0755,
               'up.cgi'      => 0755,
               'uu.cgi'      => 0755,
               'upload.cgi'     => 0755,
               'up_flash.cgi'     => 0755,
               'api.cgi'        => 0755,
               'transfer.pl'    => 0755,
               'XFileConfig.pm' => 0666,
               'XFSConfig.pm'   => 0666,
               'temp'           => 0777,
               'uploads'        => 0777,
               'logs'      => 0777,
               'Templates/static'         => 0777,
               "$c->{site_path}/files"    => 0777,
               "$c->{site_path}/i"        => 0777,
               "$c->{site_path}/captchas" => 0777,
               "$c->{site_path}/tmp"      => 0777,
               "$c->{site_path}/catalogue.rss" => 0666,
               "$c->{site_path}/sitemap.txt"   => 0666,
               "$c->{site_path}/sitemap.txt.gz" => 0666,
            };
my @arr;
for(sort keys %{$perms})
{
   next unless -e $_;
   next if /^\/\w+$/;
   chmod $perms->{$_}, $_;
   my $chmod = (stat($_))[2] & 07777;
   my $chmod_txt = sprintf("%04o", $chmod);
   push @arr, "<b>$_</b> : $chmod_txt : ".( $chmod == $perms->{$_} ? 'OK' : "<u>ERROR: should be ".sprintf("%04o",$perms->{$_})."</u>" );
}

chmod 0666, "$c->{site_path}/.htaccess" if -f "$c->{site_path}/.htaccess";
print join '<br>', @arr;
if( grep{/ERROR/}@arr )
{
   print"<br><br><font color='red'>Fix permissions above and refresh this page</font>";
}
else
{
   print"<br><br>All permissions are correct.$ok";
}

############
print"<hr>";
############

print"<b>2) Site URL / Path Settings / License Key</b><br><br>";
if($c->{site_url} && $c->{site_cgi} && $c->{site_path} && $c->{cgi_path})
{
   print"Settings are correct.$ok";
}
else
{
   my $path = $ENV{DOCUMENT_ROOT};
   my ($cgipath) = $ENV{SCRIPT_FILENAME}=~/^(.+)\//;
   my $url_cgi = 'http://'.$ENV{HTTP_HOST}.$ENV{REQUEST_URI};
   $url_cgi=~s/\/[^\/]+$//;
   my $url = 'http://'.$ENV{HTTP_HOST};
   
   $url = $c->{site_url}||$url;
   $url_cgi = $c->{site_cgi}||$url_cgi;
   $path = $c->{site_path}||$path;
   $path=~s/\/$//;
print<<EOP
<form method="POST">
<input type="hidden" name="site_settings" value="1">
Site URL:<br>
<input type="text" name="site_url" value="$url" size=48> <small>No trailing slash</small><br>
cgi-bin URL:<br>
<input type="text" name="site_cgi" value="$url_cgi" size=48> <small>No trailing slash</small><br>
cgi-bin disk path:<br>
<input type="text" name="cgi_path" value="$cgipath" size=48> <small>No trailing slash</small><br>
htdocs(public_html) disk path:<br>
<input type="text" name="site_path" value="$path" size=48> <small>No trailing slash</small><br>
License Key:<br>
<input type="text" name="license_key" value="$c->{license_key}" size=48><br>
<br>
<input type="submit" value="Save site settings">
</form>
EOP
;
}

############
print"<hr>";
############

print"<b>3) MySQL Settings</b><br><br>";
my $dbh=DBI->connect("DBI:mysql:database=$c->{db_name};host=$c->{db_host}",$c->{db_login},$c->{db_passwd}) if $c->{db_name} && $c->{db_host};
if($dbh)
{
   print"MySQL Settings are correct. Can connect to DB.$ok";
}
else
{
print<<EOP
<font color="red">Can't connect to DB with current settings. $DBI::errstr</font><br><br>
<Form method="POST">
<input type="hidden" name="save_sql_settings" value="1">
MySQL Host:<br>
<input type="text" name="db_host" value="$c->{db_host}"><br>
MySQL DB Name:<br>
<input type="text" name="db_name" value="$c->{db_name}"><br>
MySQL DB Username:<br>
<input type="text" name="db_login" value="$c->{db_login}"><br>
MySQL DB Password:<br>
<input type="text" name="db_passwd" value="$c->{db_passwd}"><br><br>
<input type="submit" value="Save MySQL Settings">
</Form>
EOP
;
}

############
print"<hr>";
############

print"<b>4) MySQL tables create & Admin account</b><br><br>";

if(!$dbh)
{
   print"<font color=red>Fix MySQL settings above first.</font>";
}
else
{
   my $sth=$dbh->prepare("DESC Files");
   my $rc=$sth->execute();
   if($rc)
   {
      print"Tables created successfully.$ok";
   }
   else
   {
print<<EOP
<form method="POST">
<input type="hidden" name="create_sql" value="1">
Admin login:<br><input type="text" name="usr_login"><br>
Admin password:<br><input type="text" name="usr_password"><br>
Admin E-mail:<br><input type="text" name="usr_email"><br><br>
<input type="submit" value="Create MySQL Tables & Admin Account">
</form>
EOP
;
   }
}

############
print"<hr>";
############

print<<EOP
5) Clean install
<form method="POST">
<input type="hidden" name="remove_install" value="1">
<input type="submit" value="Remove install files">
</form>
EOP
;

