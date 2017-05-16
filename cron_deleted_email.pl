#!/usr/bin/perl
use strict;
use XFileConfig;
use Session;
use CGI::Carp qw(fatalsToBrowser);

print "Content-type: text/html\n\n";

my $ses = Session->new();
my $db= $ses->db;

$c->{email_text}=1;

### Email warning to expiring users ###
my $users_expiring = $db->SelectARef("SELECT usr_login,usr_email 
                                      FROM Users 
                                      WHERE usr_premium_expire>NOW()
                                      AND usr_premium_expire<NOW()+INTERVAL 24 HOUR");
for my $user (@$users_expiring)
{
   my $t = $ses->CreateTemplate("email_account_expiring.html");
   $t->param(%$user);
   print"Sending account expire email to $user->{usr_login} ($user->{usr_email})\n";
   $ses->SendMail( $user->{usr_email}, $c->{email_from}, "$c->{site_name}: your Premium account expiring soon", $t->output );
}

### Deleted files ###
if($c->{deleted_files_reports}) {
   my $users = $db->SelectARef("SELECT DISTINCT usr_id FROM FilesDeleted");
   for my $u (@$users)
   {
      my $files = $db->SelectARef("SELECT file_name FROM FilesDeleted 
                      WHERE usr_id=?
                      AND deleted>NOW()-INTERVAL 24 HOUR
                      AND hide=0
                      ORDER BY file_name",$u->{usr_id});
      next if $#$files==-1;
      my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?",$u->{usr_id});
      next unless $user;
      my $text="These files were expired or deleted by administrator from your account:\n\n";
      $text.=join("\n", map{$_->{file_name}}@$files );
      $ses->SendMail( $user->{usr_email}, $c->{email_from}, "$c->{site_name}: deleted files list", $text );
      $db->Exec("DELETE FROM FilesDeleted WHERE usr_id=?",$u->{usr_id});
   }
}

$c->{email_text}=0;
### Banned users / IPs ###
if($c->{max_login_attempts_h} || $c->{max_login_ips_h}) {
   my $bans = $db->SelectARef("SELECT *, INET_NTOA(ip) AS ip2 FROM Bans
                     WHERE created > NOW() - INTERVAL 24 HOUR");
   for(@$bans) {
      $_->{usr_login} = $db->SelectOne("SELECT usr_login FROM Users WHERE usr_id=?", $_->{usr_id});
      $_->{usr_login} =~ s/[<>]//g;
   }
   my @bans_users = grep { $_->{usr_id} } @$bans;
   my @bans_ips = grep { $_->{ip} } @$bans;
   if(@bans_ips || @bans_users) {
	   my $tmpl = $ses->CreateTemplate("ban_notification_admin.html");
      $tmpl->param(
                  bans_ips => \@bans_ips,
                  bans_users => \@bans_users,
                  site_url => $c->{site_url},
                  );
      $ses->SendMail( $c->{contact_email}, $c->{email_from}, "$c->{site_name}: Security report", $tmpl->output() );
   }
}
