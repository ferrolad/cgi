package index_m;

### SibSoft.net ###
use strict;
use lib '.';
use lib 'Plugins';
use vars qw($ses);
use XFileConfig;
use Session;
use CGI::Carp qw(fatalsToBrowser);
use XUtils;
use JSON;
use URI::Escape;
use List::Util qw(min);
use Log;

Log->new(filename => 'index.log');
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

my ($ses, $db, $f, $op, $utype);

sub run {
   my ($query) = @_;
   $c->{ip_not_allowed}=~s/\./\\./g;
   if($c->{ip_not_allowed} && $ENV{REMOTE_ADDR}=~/^($c->{ip_not_allowed})$/)
   {
      print"Content-type:text/html\n\n";
      print"Your IP was banned by administrator";
      return;
   }

   $c->{no_session_exit}=1;
   $ses = Session->new($query);
   $f = $ses->f;
   $op = $f->{op};

   if($c->{m_n}){ $c->{$_} = 1 for qw(direct_links_anon direct_links_reg direct_links_prem); }

   if($f->{design}=~/^(\d+)$/)
   {
      $ses->setCookie("design",$1,'+300d');
      return $ses->redirect($c->{site_url});
   }

   &ChangeLanguage if $f->{lang};

   if ( !$op && $f->{logout} )
   {
      my $usr_id = $ses->getCookie( "mangle_id" );
      $ses->setCookie( "mangle_id", 0 );
      return $ses->redirect("$c->{site_url}/?op=admin_user_edit&usr_id=$usr_id");
   }

   $db= $ses->db;

   XUtils::CheckAuth($ses);
   if($ses->getUser && $op !~ /^(my_account|logout)$/)
   {
      return $ses->redirect_msg("$c->{site_url}/?op=my_account", "Please enter your new password")
         if !$ses->getUser->{usr_password};
      return $ses->redirect_msg("$c->{site_url}/?op=my_account", "Please enter your e-mail")
         if !$ses->getUser->{usr_email};
   }
   return $ses->message($c->{maintenance_full_msg}||"The website is under maintenance.","Site maintenance") if $c->{maintenance_full} && $f->{op}!~/^(admin_|login)/i;

   $ses->{lang}->{dmca_agent} = $ses->getUser && $ses->getUser->{usr_dmca_agent} ? 1 : 0;
   $ses->{lang}->{approve_count} = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_awaiting_approve") if $ses->getUser && ($ses->getUser->{usr_mod} || $ses->getUser->{usr_adm});
   $ses->{lang}->{del_confirm_request_count} = $db->SelectOne("SELECT COUNT(*) FROM Misc WHERE name='mass_del_confirm_request'") if $ses->getUser && $ses->getUser->{usr_adm};
   
   $utype = $ses->getUser ? ($ses->getUser->{premium} ? 'prem' : 'reg') : 'anon';
  
   $c->{$_}=$c->{"$_\_$utype"} for qw(max_upload_files
                                      disk_space
                                      max_upload_filesize
                                      download_countdown
                                      max_downloads_number
                                      captcha
                                      ads
                                      bw_limit
                                      remote_url
                                      leech
                                      direct_links
                                      down_speed
                                      max_rs_leech
                                      add_download_delay
                                      max_download_filesize
                                      torrent_dl
                                      torrent_dl_slots
                                      torrent_fallback_after
                                      video_embed
                                      flash_upload
                                      rar_info
                                      upload_on
                                      download_on
                                      m_n_limit_conn
                                      m_n_dl_resume
                                      m_n_upload_speed
                                      ftp_upload
                                      );
   
   my $sub={
       login         => \&LoginPage,
       news          => \&News,
       news_details  => \&NewsDetails,
       contact       => \&Contact,
       registration  => \&Register,
       register_save => \&RegisterSave,
       resend_activation => \&ResendActivationCode,
       upload_result => \&UploadResult,
       download1     => \&Download1,
       download2     => \&Download2,
       page          => \&Page,
       forgot_pass   => \&ForgotPass,
       contact_send  => \&ContactSend,
       user_public   => \&UserPublic,
       payments      => \&Payments,
       checkfiles    => \&CheckFiles,
       catalogue     => \&Catalogue,
       change_lang   => \&ChangeLanguage,
       report_file   => \&ReportFile,
       report_file_send => \&ReportFileSend,
       api_get_limits => \&APIGetLimits,
       comment_add   => \&CommentAdd,
       cmt_del       => \&CommentDel,
       del_file      => \&DelFile,
       links         => \&Links,
       video_embed   => \&VideoEmbed,
       unsubscribe   => \&EmailUnsubscribe,
       api_reseller  => \&APIReseller,
       register_ext  => \&RegisterExt,
       external      => \&External,
       upload        => \&UploadForm,
       make_money    => \&MakeMoney,
            }->{ $op };
   return &$sub() if $sub;
   
   return &PaymentComplete($1) if $ENV{QUERY_STRING}=~/payment_complete=(.+)/;
   return &RegisterConfirm() if $f->{confirm_account};
   
   $sub={
           
       my_account       => \&MyAccount,
       my_referrals     => \&MyReferrals,
       my_files         => \&MyFiles,
       my_files_export  => \&MyFilesExport,
       my_files_deleted  => \&MyFilesDeleted,
       my_reports       => \&MyReports,
       my_reseller      => \&MyReseller,
       file_edit        => \&FileEdit,
       fld_edit         => \&FolderEdit,
       request_money    => \&RequestMoney,
       mass_dmca        => \&MassDMCA,
       admin_files      => \&AdminFiles,
       admin_users      => \&AdminUsers,
       admin_file_edit  => \&FileEdit,
       admin_user_edit  => \&AdminUserEdit,
       admin_users_add  => \&AdminUsersAdd,
       admin_servers    => \&AdminServers,
       admin_server_add => \&AdminServerAdd,
       admin_server_save=> \&AdminServerSave,
       admin_server_del => \&AdminServerDelete,
       admin_settings   => \&AdminSettings,
       admin_news       => \&AdminNews,
       admin_news_edit  => \&AdminNewsEdit,
       admin_reports    => \&AdminReports,
       admin_update_srv_stats  => \&AdminUpdateServerStats,
       admin_server_import     => \&AdminServerImport,
       admin_mass_email => \&AdminMassEmail,
       admin_downloads  => \&AdminDownloads,
       admin_comments   => \&AdminComments,
       admin_comment_edit => \&AdminCommentEdit,
       admin_payments   => \&AdminPayments,
       admin_stats      => \&AdminStats,
       admin_torrents      => \&AdminTorrents,
       admin_anti_hack     => \&AdminAntiHack,
       admin_user_referrals=> \&AdminUserReferrals,
       admin_transfer_list => \&AdminTransferList,
       admin_servers_transfer => \&AdminServersTransfer,
       admin_ipn_logs      => \&AdminIPNLogs,
       admin_bans_list     => \&AdminBansList,
       admin_sites         => \&AdminSites,
       admin_external   => \&AdminExternal,
       moderator_approve   => \&AdminApprove,
       admin_approve   => \&AdminApprove,
       moderator_files     => \&ModeratorFiles,
       logout           => sub{$ses->Logout},
   
       }->{ $op };
   
   if($sub && $ses->getUser)
   {
      return $ses->message("Access denied") if $op=~/^admin_/i && !$ses->getUser->{usr_adm} && $op!~/^(admin_reports|admin_comments|admin_approve)$/i;
      return &$sub();
   }
   elsif($sub)
   {
      $f->{redirect}=$ENV{REQUEST_URI};
      return &LoginPage();
   }
   elsif ( $f->{login_as} )
   {
      $ses->setCookie( "mangle_id", $f->{login_as} );
      return $ses->redirect($c->{site_url});
   }
   elsif ( $f->{logout} )
   {
      my $usr_id = $ses->getUserId;
      $ses->setCookie( "mangle_id", 0 );
      return $ses->redirect("$c->{site_url}/?op=admin_user_edit&usr_id=$usr_id");
   }
   elsif ( $c->{show_splash_main} )
   {
      return &SplashScreen();
   }
   else
   {
      return &UploadForm();
   }
}

sub CheckReferer
{
   return $ses->getDomain($_[0]) eq $ses->getDomain($c->{site_url});
}

sub LoginPage
{

   return $ses->redirect($c->{site_url}) if $ses->getUser;
   return &Login() if $f->{method};
   if($f->{login})
   {
      &Login();
      $f->{msg}||=$ses->{lang}->{lang_login_pass_wrong} unless $ses->getUser;
   }
   $f->{login}||=$ses->getCookie('login');
   $f->{redirect} ||= $ENV{HTTP_REFERER},

  my $login_attempts_h = $db->SelectOne("SELECT COUNT(ip)
           FROM LoginProtect
         WHERE usr_id=0
         AND ip=INET_ATON(?)
         AND created >= NOW() - INTERVAL 1 HOUR",
         $ses->getIP);

   $ses->setCaptchaMode($c->{captcha_mode}||2) if $c->{captcha_attempts_h} && $login_attempts_h >= $c->{captcha_attempts_h};
   my %secure = $ses->SecSave( 0, 0 ) if $ses->{captcha_mode};

   return $ses->PrintTemplate("login.html",
      %{$f},
      %{$c},
      %secure,
      );
}

sub RegisterExt
{
   return $ses->message("Not allowed") if !$c->{m_c};
   return $ses->redirect("$c->{site_url}/?op=my_account") if $ses->getUser;
   my $ret = eval { $ses->getPlugins('Login')->finish($f) };
   print STDERR "mod_social: $@\n" if $@;
   return $ses->message("Auth failed") if !$ret;
   # Does the user already exists?

   my $passwd_hash = XUtils::GenPasswdHash($f->{usr_password});

   my $usr_id = $db->SelectOne("SELECT usr_id
            FROM Users
            WHERE usr_social=?
            AND usr_social_id=?",
            $f->{method},
            $ret->{usr_social_id});
   if(!$usr_id)
   {
      # Creating the new one
      my $profit_mode = $ses->iPlg('p') && $c->{m_y_default} ? $c->{m_y_default} : 'PPD';

      $db->Exec("INSERT INTO Users SET usr_login=?,
            usr_password=?,
            usr_status='OK',
            usr_email=?,
            usr_social=?,
            usr_social_id=?,
            usr_profit_mode=?,
            usr_created=NOW()",
            $ret->{usr_login},
            $passwd_hash,
            $ret->{usr_email}||'',
            $f->{method},
            $ret->{usr_social_id},
            $profit_mode,
          );
      $usr_id = $db->getLastInsertId;
      if($f->{method} eq 'twitter')
      {
         # Pre-filling data for twitter posting
         $ses->setUserData($usr_id, 'twitter_login', $ret->{access_token});
         $ses->setUserData($usr_id, 'twitter_password', $ret->{access_token_secret});
      }
   }
   $f->{method} = '';
   &Login(usr_id => $usr_id);
}

sub StartSession
{
   my ($usr_id) = @_;
   my $sess_id = $ses->randchar(16);
   $db->Exec("DELETE FROM Sessions WHERE last_time + INTERVAL 5 DAY < NOW()");
   $db->Exec("INSERT INTO Sessions (session_id,usr_id,last_time) VALUES (?,?,NOW())",$sess_id,$usr_id);
   return $sess_id;
}

sub GetSession
{
   my ($usr_id) = @_;
   my $session = $db->SelectRow("SELECT * FROM Sessions WHERE usr_id=?", $usr_id);
   return $session ? $session->{session_id} : &StartSession($usr_id);
}

sub Login
{
  my %opts = @_;

  # Brute-forcers protect
  my $login_attempts_h = $db->SelectOne("SELECT COUNT(ip)
           FROM LoginProtect
         WHERE usr_id=0
         AND ip=INET_ATON(?)
         AND created >= NOW() - INTERVAL 1 HOUR",
         $ses->getIP);

  if($c->{captcha_attempts_h} && $login_attempts_h >= $c->{captcha_attempts_h})
  {
     $ses->setCaptchaMode($c->{captcha_mode}||2);
     if(!$ses->SecCheck( $f->{'rand'}, 0, $f->{code} ))
     {
	     delete $ses->{user};
	     $f->{msg} = "Wrong captcha";
	     return;
     }
  }

  if($c->{max_login_attempts_h} && $login_attempts_h >= $c->{max_login_attempts_h})
  {
     XUtils::Ban($ses, ip => $ses->getIP,
      reason => 'bruteforce');
  }
  if($db->SelectOne("SELECT ip FROM Bans WHERE ip=INET_ATON(?)", $ses->getIP))
  {
     delete $ses->{user};
     $f->{msg} = "Your IP is banned";
     return;
  }
  ($f->{login}, $f->{password}) = split(':',$ses->decode_base64($ENV{HTTP_CGI_AUTHORIZATION})) if $opts{instant};
  $f->{login}=$ses->SecureStr($f->{login});
  $f->{password}=$ses->SecureStr($f->{password});
  my $usr_id;

  if($f->{method})
  {
     # Login through the external plugins
     my $url = $ses->getPlugins('Login')->get_auth_url($f);
     return $ses->message("Login failed") if !$url;
     return $ses->redirect($url);
  }

  $ses->{user} = XUtils::GetUser($ses, $opts{usr_id}) || XUtils::CheckLoginPass($ses, $f->{login}, $f->{password});

  $db->Exec("INSERT INTO LoginProtect SET usr_id=?, login=?, ip=INET_ATON(?)",
        $ses->{user} ? $ses->getUserId : 0,
           $f->{login},
      $ses->getIP) if $f->{login};

  unless($ses->{user})
  {
     return undef;
  }
  
  $ses->{user}->{premium}=1 if $ses->{user}->{exp_sec}>0;
  if($ses->{user}->{usr_status} eq 'PENDING')
  {
     my $id = $ses->{user}->{usr_id}."-".$ses->{user}->{usr_login};
     delete $ses->{user};
     $f->{msg} ||= "Your account haven't confirmed yet.<br>Check your e-mail for confirm link or contact site administrator.<br>Or try to <a href='?op=resend_activation&d=$id'>resend activation email</a>";
     return;
  }
  # Accounts sharing protect
  my $login_ips_h = $db->SelectOne("SELECT COUNT(DISTINCT(ip))
           FROM LoginProtect
         WHERE usr_id=?
         AND created >= NOW() - INTERVAL 1 HOUR",
         $ses->getUserId);
  if($c->{max_login_ips_h} && $login_ips_h >= $c->{max_login_ips_h})
  {
     XUtils::Ban($ses, usr_id => $ses->getUserId,
      reason => 'multilogin');
  }
  return if $opts{instant};

  $db->Exec("DELETE FROM LoginProtect WHERE usr_id=0 AND ip=INET_ATON(?)", $ses->getIP);

  my $sess_id = &StartSession($ses->{user}->{usr_id});
  $db->Exec("UPDATE Users SET usr_lastlogin=NOW(), usr_lastip=INET_ATON(?) WHERE usr_id=?", $ses->getIP, $ses->{user}->{usr_id} );
  $ses->setCookie( $ses->{auth_cook} , $sess_id, '+30d' );
  $ses->setCookie('login',$f->{login},'+6M');

  if($ses->getUser->{usr_notes}=~/^payments/)
  {
     my ($type,$amount) = $ses->getUser->{usr_notes}=~/^payments-(\w+)-([\d\.]+)/;
     $db->Exec("UPDATE Users SET usr_notes='' WHERE usr_id=?",$ses->getUserId);
     return $ses->redirect("?op=payments&type=$type&amount=$amount");
  }

  $f->{redirect}="$c->{site_url}/$f->{redirect}" if $f->{redirect}=~/^\w{12}$/;
  return $ses->redirect( $f->{redirect} ) if $f->{redirect} && $f->{redirect} =~ /^\Q$c->{site_url}\E/;
  $ses->redirect( "$c->{site_url}/?op=my_files" ) unless $opts{no_redirect};
  return $ses->{user};
};

sub Register
{
   return $ses->redirect($c->{site_url}) if $ses->getUser;
   return $ses->message("Registration disabled") if !$c->{reg_enabled};
   my $msg = shift;
   $ses->setCaptchaMode($c->{captcha_mode}||2);
   my %secure = $ses->SecSave( 0, 0 );
   $f->{usr_login}=$ses->SecureStr($f->{usr_login});
   $f->{usr_email}=$ses->SecureStr($f->{usr_email});
   if($f->{aff_id}=~/^(\d+)$/i)
   {
      $ses->setCookie("aff",$1,'+14d');
   }
   my @payout_list = map{ {name=>$_} } split(/\s*\,\s*/,$c->{payout_systems});
   $ses->PrintTemplate("registration.html",
                       %secure,
                       %{$c},
                       'usr_login' => $f->{usr_login},
                       'usr_email' => $f->{usr_email},
                       'usr_password'  => $f->{usr_password},
                       'usr_password2' => $f->{usr_password2},
                       'coupons'       => $c->{coupons}, 
                       'coupon_code'   => $f->{coupon_code}||$f->{coupon},
                       'usr_pay_email' => $f->{usr_pay_email},
                       "pay_type_$f->{usr_pay_type}"  => 1,
                       'msg'           => $f->{msg}||$msg,
                       'paypal_email'        => $c->{paypal_email},
                       'alertpay_email'      => $c->{alertpay_email},
                       'webmoney_merchant_id'=> $c->{webmoney_merchant_id},
                       'next'          => $f->{'next'},
                       'payout_list'         => \@payout_list,
                      );
}

sub RegisterSave
{
   $ses->setCaptchaMode($c->{captcha_mode}||2);
   return $ses->redirect("Registration disabled") if !$c->{reg_enabled};
   return &Register unless $ses->SecCheck( $f->{'rand'}, 0, $f->{code} );
   return &Register("Error: $ses->{lang}->{lang_login_too_short}") if length($f->{usr_login})<4;
   return &Register("Error: $ses->{lang}->{lang_login_too_long}") if length($f->{usr_login})>32;
   return &Register("Error: Invalid login: reserved word") if $f->{usr_login}=~/^(admin|images|captchas|files)$/;
   return &Register("Error: $ses->{lang}->{lang_invalid_login}") unless $f->{usr_login}=~/^[\w\-\_]+$/;
   return &Register("Error: Password contain bad symbols") if $f->{usr_password}=~/[<>"]/;
   return &Register("Error: $ses->{lang}->{lang_pass_too_short}") if length($f->{usr_password})<4;
   return &Register("Error: $ses->{lang}->{lang_pass_too_long}") if length($f->{usr_password})>32;
   return &Register("Error: $ses->{lang}->{lang_pass_dont_match}") if $f->{usr_password} ne $f->{usr_password2};
   return &Register("Error: $ses->{lang}->{lang_invalid_email}") unless $f->{usr_email}=~/^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
   return &Register("Error: $ses->{lang}->{lang_mailhost_banned}") if $c->{mailhosts_not_allowed} && $f->{usr_email}=~/\@$c->{mailhosts_not_allowed}/i;
   return &Register("Error: $ses->{lang}->{lang_login_exist}")  if $db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{usr_login});
   return &Register("Error: $ses->{lang}->{lang_email_exist}") if $db->SelectOne("SELECT usr_id FROM Users WHERE usr_email=?",$f->{usr_email});
   my $confirm_key = $ses->randchar(8) if $c->{registration_confirm_email};
   my $usr_status = $confirm_key ? 'PENDING' : 'OK';
   my $premium_days=0;
   $f->{coupon_code} = lc $f->{coupon_code};
   my $aff = $ses->getCookie('aff')||0;

   if($c->{coupons} && $f->{coupon_code})
   {
      my $hh;
      for(split(/\|/,$c->{coupons}))
      {
         $hh->{lc($1)}=$2 if /^(.+?)=(\d+)$/;
      }
      $premium_days = $hh->{$f->{coupon_code}};
      &Register("Invalid coupon code") unless $premium_days;
   }
   my $profit_mode = $ses->iPlg('p') && $c->{m_y_default} ? $c->{m_y_default} : 'PPD';
   my $usr_notes=$f->{'next'}||'';
   my $passwd_hash = XUtils::GenPasswdHash($f->{usr_password});

   $db->Exec("INSERT INTO Users 
              SET usr_login=?, 
                  usr_email=?, 
                  usr_password=?,
                  usr_created=NOW(),
                  usr_premium_expire=NOW()+INTERVAL ? DAY,
                  usr_security_lock=?,
                  usr_status=?,
                  usr_aff_id=?,
                  usr_pay_email=?, 
                  usr_pay_type=?,
                  usr_profit_mode=?,
                  usr_notes=?",
                                   $f->{usr_login},
                                   $f->{usr_email},
                                   $passwd_hash,
                                   $premium_days,
                                   $confirm_key||'',
                                   $usr_status,
                                   $aff,
                                   $f->{usr_pay_email}||'',
                                   $f->{usr_pay_type}||'',
                                   $profit_mode,
                                   $usr_notes);
   my $usr_id=$db->getLastInsertId;
   $db->Exec("INSERT INTO Stats SET day=CURDATE(), registered=1 ON DUPLICATE KEY UPDATE registered=registered+1");
   if($confirm_key)
   {
      my $t = $ses->CreateTemplate("registration_email.html");
      $t->param( 'usr_login'=>$f->{usr_login}, 'usr_password'=>$f->{usr_password}, 'confirm_id'=>"$usr_id-$confirm_key" );
      $c->{email_text}=1;
      $ses->SendMail($f->{usr_email},$c->{email_from},"$c->{site_name} registration confirmation",$t->output);
      return $ses->PrintTemplate('message.html',
                  err_title => 'Account created',
            msg => $ses->{lang}->{lang_account_created});
   }

   my $err = $ses->ApplyPlugins('user_new', $f->{usr_login}, $f->{usr_password}, $f->{usr_email});
   return $ses->message("Registration complete but there were plugin errors:<br><br>$err") if $err;

   $f->{login}    = $f->{usr_login};
   $f->{password} = $f->{usr_password};
   &Login();

   return $ses->redirect( $c->{site_url} );
}

sub RegisterConfirm
{
   my ($usr_id,$confirm_key)=split('-',$f->{confirm_account});
   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=? AND usr_security_lock=?",$usr_id,$confirm_key);
   unless($user)
   {
      return $ses->message("Invalid confirm code");
   }
   return $ses->message("Account already confirmed") if $user->{usr_status} ne 'PENDING';
   $db->Exec("UPDATE Users SET usr_status='OK', usr_security_lock='' WHERE usr_id=?",$user->{usr_id});
   my $sess_id = &StartSession($user->{usr_id});
	$ses->setCookie( $ses->{auth_cook} , $sess_id, '+30d' );

   return $ses->redirect( $c->{site_url}.'?msg=Account confirmed' );
}

sub ResendActivationCode
{
   my ($adm_mode) = @_;
   ($f->{usr_id},$f->{usr_login}) = split(/-/,$f->{d});
   my $user = $db->SelectRow("SELECT usr_id,usr_login,usr_email,usr_security_lock
                              FROM Users
                              WHERE usr_id=?
                              AND usr_login=?",$f->{usr_id},$f->{usr_login});
   return $ses->message("Invalid ID") unless $user;

   my $t = $ses->CreateTemplate("registration_email.html");
   $t->param( 'usr_login'=>$user->{usr_login}, 'usr_password'=>$user->{usr_password}, 'confirm_id'=>"$user->{usr_id}-$user->{usr_security_lock}" );
   $c->{email_text}=1;
   $ses->SendMail($user->{usr_email},$c->{email_from},"$c->{site_name} registration confirmation",$t->output);
   return $ses->redirect_msg("?op=admin_users","Activation email sent") if $adm_mode;
   return $ses->message("Activation email just resent.<br>To activate it follow the activation link sent to your e-mail.");
}

sub ForgotPass
{
   $ses->setCaptchaMode($c->{captcha_mode}||2);
   return $ses->redirect($c->{site_url}) if $ses->getUser;
   my ($no_redirect) = @_;
   if($f->{sess})
   {
      my $session = $db->SelectRow("SELECT * FROM Sessions
                      WHERE session_id=?", $f->{sess});
      return $ses->message("Wrong session") if !$session;
      my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $session->{usr_id});
      $db->Exec("DELETE FROM Sessions WHERE usr_id=?",
                      $user->{usr_id});
      if($user->{usr_security_lock})
      {
         return $ses->message("Error: security code doesn't match")
            if $f->{code} ne $user->{usr_security_lock};
         $db->Exec("UPDATE Users SET usr_security_lock='' WHERE usr_id=?",
                         $user->{usr_id});
      }
      my $new_sess_id = $ses->randchar(16);
      $db->Exec("UPDATE Sessions SET session_id=? WHERE usr_id=?", $new_sess_id, $session->{usr_id});
      $db->Exec("INSERT INTO Sessions (session_id,usr_id,last_time) VALUES (?,?,NOW())",
                  $new_sess_id,
                  $session->{usr_id});
      $ses->setCookie( $ses->{auth_cook} , $new_sess_id, '+30d' );
      $db->Exec("UPDATE Users SET usr_password='', usr_security_lock='' WHERE usr_id=?",
                      $user->{usr_id});
      return $ses->redirect($c->{site_url});
   }
   if($f->{usr_login} && !$no_redirect)
   {
      return &ForgotPass('no_redirect') if(!$ses->SecCheck( $f->{'rand'}, 0, $f->{code} ));
      my $user = $db->SelectRow("SELECT * FROM Users 
                                 WHERE (usr_login=? 
                                 OR usr_email=?)",
             $f->{usr_login},
             $f->{usr_login});
      return $ses->message($ses->{lang}->{lang_no_login_email}) unless $user;
      my $sess_id = $ses->randchar(16);
      $db->Exec("INSERT INTO Sessions (session_id,usr_id,last_time) VALUES (?,?,NOW())",
                  $sess_id,
            $user->{usr_id});
      my $link = "$c->{site_url}/?op=forgot_pass&sess=$sess_id";
      $link .= "&code=$user->{usr_security_lock}" if $user->{usr_security_lock};
      $ses->SendMail( $user->{usr_email}, $c->{email_from}, "$c->{site_name}: password recovery", "Please follow this link to continue recovery:\n<a href=\"$link\">$link</a>" );
      return $ses->PrintTemplate("message.html",
         err_title => "Notice",
         msg => "Password recovery link sent to your e-mail");
   }
   $f->{usr_login} = $ses->SecureStr($f->{usr_login});
   my %secure = $ses->SecSave( 0, 0 );
   $ses->PrintTemplate("forgot_pass.html",
         %{$f},
            %secure,
         );
};

sub genUploadURL
{
   my ($server, $usr_id, $speed) = @_;
   use Digest::MD5 qw(md5);
   require HCE_MD5;
   my $hce = HCE_MD5->new($c->{dl_key}, "XFileSharingPRO");
   my $usr_id = $ses->getUserId if $ses->getUser;

   my @data = ($server->{srv_id}, time + 8 * 3600, $speed * 1024);
   my $md5 = md5(join('', @data));
   my $hash = $ses->encode32( $hce->hce_block_encrypt(pack("SLLA32", @data, $md5)) );
   return "$1:182/u/?upload_type=file&token=$hash" if $server->{srv_htdocs_url} =~ /^(https?:\/\/[^\/]+)/;
}

sub UploadForm
{
   return $ses->message($c->{maintenance_upload_msg}||"Uploads are temporarily disabled due to site maintenance","Site maintenance") if $c->{maintenance_upload};
   return $ses->redirect("?op=login") if !$c->{enabled_anon} && !$ses->getUser;
   $ses->redirect("?op=login") if !$c->{upload_on} && $utype eq 'anon';
   return $ses->message("Uploads are disabled for your user type","Upload error") if !$c->{upload_on};
   if($c->{upload_disabled_countries} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      my $country = $gi->country_code_by_addr($ses->getIP);
      for(split(/\s*\,\s*/,$c->{upload_disabled_countries}))
      {
          return $ses->message("Uploads are disabled for your country: $country") if $_ eq $country;
      }
   }

   my $server = XUtils::SelectServer($ses, $ses->{user});
   my $server_torrent = XUtils::SelectServer($ses, $ses->{user}, "srv_torrent=1");
   $server = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?",$f->{srv_id}) if $ses->getUser && $ses->getUser->{usr_adm} && $f->{srv_id};
   
   return $ses->redirect('?op=admin_server_add') if !$server && $ses->getUser && $ses->getUser->{usr_adm};
   return $ses->message("We're sorry, there are no servers available for upload at the moment.<br>Refresh this page in some minutes.") unless $server;
   $server->{srv_htdocs_url}=~s/\/(\w+)$//;
   $server->{srv_tmp_url} = "$server->{srv_htdocs_url}/tmp";
   $server_torrent->{srv_htdocs_url}=~s/\/(\w+)$//;
   $server_torrent->{srv_tmp_url} = "$server_torrent->{srv_htdocs_url}/tmp";
   my @url_fields = map{{ 'number'=>$_, 'enable_file_descr'=>$c->{enable_file_descr} }} (1..$c->{max_upload_files});
   my @folders_tree = &buildFoldersTree(usr_id => $ses->getUserId);

   my $stats;
   if($c->{show_server_stats})
   {
      $stats = $db->SelectRow("SELECT SUM(srv_files) as files_total, ROUND(SUM(srv_disk)/1073741824,2) as used_total FROM Servers");
      $stats->{user_total} = $db->SelectOne("SELECT COUNT(*) FROM Users");
   }

   my $mmrr=$c->{"\x6d\x5f\x72"};
   my ($leech_on,$leech_left_mb);
   if($c->{max_rs_leech} && $ses->getUser)
   {
      $leech_left_mb = ($ses->getUser->{usr_max_rs_leech}||$c->{max_rs_leech}) - $db->SelectOne("SELECT ROUND(SUM(size)/1048576) FROM IP2RS WHERE created>NOW()-INTERVAL 24 HOUR AND (usr_id=? OR ip=INET_ATON(?))",$ses->getUserId,$ses->getIP);
      $leech_left_mb=0 if $leech_left_mb<0;
      $leech_on=1 if $c->{remote_url}; #$leech_left_mb>0 &&
   }

   my $mmtt=$ses->iPlg('t');
   my $mmtt_on = $mmtt && $c->{"\x74\x6f\x72\x72\x65\x6e\x74\x5f\x64\x6c"};
   #$mmtt=0 unless $server_torrent->{srv_id};
   my $tt_msg;
   if($mmtt && !$server_torrent->{srv_id})
   {
      $mmtt_on=0;
      $tt_msg.=$ses->{lang}->{lang_no_torrent_srv}."<br>";
   }
   if($mmtt && $c->{torrent_dl_slots} && $db->SelectOne("SELECT COUNT(*) FROM Torrents WHERE usr_id=? AND status='WORKING'",$ses->getUserId)>=$c->{torrent_dl_slots})
   {
      $mmtt_on=0;
      $tt_msg.=$ses->{lang}->{lang_full_torr_slots}." ($c->{torrent_dl_slots})<br>";
   }

   my $mmff=$ses->iPlg('f');
   my $mmff_on = $mmff && $c->{flash_upload};
   my $exts = join ';', map{"*.$_"} split(/\|/,$c->{ext_allowed});
   my $exts2 = join ':', map{"*.$_"} split(/\|/,$c->{ext_allowed});
   $exts2||='*.*';

   my $udata = $ses->getUserData;
   my $sites = &getPluginsOptions('Leech', $udata) if $leech_on;
   my @supported;
   for(@$sites)
   {
      push @supported, $_->{domain} if $udata->{$_->{name}} || $c->{$_->{name}};
   }

   my $supported_sites = join ', ', sort @supported;

   my $data = $db->SelectARef("SELECT name,value FROM UserData WHERE usr_id=?",$ses->getUserId);
   my @site_logins = map{ {name=>$_->{name},value=>$_->{value}} } grep{$_->{name}=~/_logins$/i && $_->{value}} @$data;

   my $ftp_servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_ftp AND srv_status!='OFF' ORDER BY srv_id") if $c->{ftp_mod} && $utype ne 'anon';
   my $i = 1;
   for(@$ftp_servers)
   {
      $_->{name} = "FTP" . ($i++);
      $_->{usr_login} = $ses->getUser->{usr_login};
      $_->{host} = $1 if $_->{srv_htdocs_url} =~ /^https?:\/\/([^:\/]+)/;
   }

   my $usr_id = $ses->getUserId if $ses->getUser;

   my $file_upload_url = $c->{m_n} && $c->{m_n_upload_speed}
      ? &genUploadURL($server, $usr_id, $c->{m_n_upload_speed})
      : "$server->{srv_cgi_url}/upload.cgi?upload_type=file";

   my $proto = $ENV{HTTPS} eq 'on' ? 'https' : 'http';
   $file_upload_url =~ s/^https?/$proto/;

   my $domain = $1 if $c->{site_url} =~ /^https?:\/\/([^\/]+)/;

   $ses->PrintTemplate("upload_form.html",
                       'ext_allowed'      => $c->{ext_allowed},
                       'ext_not_allowed'  => $c->{ext_not_allowed},
                       'max_upload_files' => $c->{max_upload_files},
                       'max_upload_files_rows' => $c->{max_upload_files}<=10 ? $c->{max_upload_files} : 10,
                       'max_upload_filesize' => $c->{max_upload_filesize},
                       'max_upload_filesize_bytes' => $c->{max_upload_filesize}*1024*1024,
                       'enable_file_descr'=> $c->{enable_file_descr},
                       'remote_url'       => $c->{remote_url},
                       'sanitize_filename'    => $c->{sanitize_filename},
                       'add_filename_postfix' => $c->{add_filename_postfix},
                       'm_i_adult'            => $c->{m_i_adult},
                       'ftp_mod'          => $utype ne 'anon' ? $c->{ftp_mod} : 0,
                       'ftp_upload_user'  => $c->{ftp_upload},
                       'domain'		      => $domain,

                       'srv_cgi_url'      => $server->{srv_cgi_url},
                       'srv_tmp_url'      => $server->{srv_tmp_url},
                       'srv_htdocs_url'   => $server->{srv_htdocs_url},

                       'srv_torrent_cgi_url' => $server_torrent->{srv_cgi_url},
                       'srv_torrent_tmp_url' => $server_torrent->{srv_tmp_url},

                       'ftp_servers'         => $ftp_servers,

                       'sess_id'          => $ses->getCookie( $ses->{auth_cook} ),
                       'folders_tree'     => \@folders_tree,
                       'mmrr'             => $mmrr,
                       'mmtt'             => $mmtt,
                       'mmtt_on'          => $mmtt_on,
                       'tt_msg'           => $tt_msg,
                       'mmff'             => $mmff,
                       'mmff_on'          => $mmff_on,
                       'utype'            => $utype,
                       'url_fields'       => \@url_fields,
                       'supported_sites'  => $supported_sites,
                       'exts'             => $exts,
                       'exts2'            => $exts2,
                       'leech_left_mb'    => $leech_left_mb,
                       'leech_on'         => $leech_on,
                       %{$stats},
                       'site_logins'      => \@site_logins,
                       'max_rs_leech'     => $c->{max_rs_leech},
                       'rnd'              => $ses->randchar(6),
                       "link_format_$c->{link_format}" => 1,
                       "users_total"      => $db->SelectOne("SELECT COUNT(*) FROM Users"),
                       'file_public_default' => $c->{file_public_default}||0,
                       'agree_tos_default' => $c->{agree_tos_default}||0,
                       'file_upload_url'  => $file_upload_url,
                      );
}

sub SplashScreen
{
   $ses->PrintTemplate('splash.html');
}

sub UploadResult
{
   my $fnames      = &ARef($f->{'fn'});
   my $status      = &ARef($f->{'st'});

   my @arr;return if $c->{site_url}!~/\/\/(www\.|)$ses->{dc}/i || !$ses->{dc};
   
   my %features;
   for(my $i=0;$i<=$#$fnames;$i++)
   {
      $fnames->[$i] = $ses->SecureStr($fnames->[$i]);
      $status->[$i] = $ses->SecureStr($status->[$i]);
      unless($status->[$i] eq 'OK')
      {
          push @arr, {file_name => $fnames->[$i],'error' => " $status->[$i]"};
          next;
      }
      my $file = $db->SelectRow("SELECT f.*, s.srv_htdocs_url
                                 FROM Files f, Servers s
                                 WHERE f.file_code=?
                                 AND f.srv_id=s.srv_id
                                 AND f.file_created > NOW()-INTERVAL 15 MINUTE",$fnames->[$i]);
      next unless $file;
      $file->{file_size2} = $file->{file_size};
      $file->{file_size} = $ses->makeFileSize($file->{file_size});
      $file->{download_link} = $ses->makeFileLink($file);
      $file->{delete_link} = "$file->{download_link}?killcode=$file->{file_del_id}";
      if($c->{m_i} && $file->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i)
      {
         $features{has_image_url} = 1 if $c->{m_i_hotlink_orig};
         $ses->getThumbLink($file);
      }
      if($c->{m_v} && $c->{video_embed} && $file->{file_spec}=~/^V/)
      {
         my @fields=qw(vid vid_length vid_width vid_height vid_bitrate vid_audio_bitrate vid_audio_rate vid_codec vid_audio_codec vid_fps);
         my @vinfo = split(/\|/,$file->{file_spec});
         $file->{$fields[$_]}=$vinfo[$_] for (0..$#fields);
         $file->{vid_width}||=400;
         $file->{vid_height}||=300;
         $file->{vid_height}+=24;
         $features{has_video_embed_code} = $file->{video_embed_code} = 1;
      }
      if($c->{m_j})
      {
         $features{has_deurl} = 1;
         $file->{deurl} = $ses->shortenURL($file->{file_id}) if $c->{m_j};
      }
      $file->{forum_code} = $file->{thumb_url} ? "[URL=$file->{download_link}][IMG]$file->{thumb_url}\[\/IMG]\[\/URL]" : "[URL=$file->{download_link}]$file->{file_name} -  $file->{file_size}\[\/URL]";
      $file->{html_code} = $file->{thumb_url} ? qq[<a href="$file->{download_link}" target=_blank><img src="$file->{thumb_url}" border=0><\/a>] : qq[<a href="$file->{download_link}" target=_blank>$file->{file_name} - $file->{file_size}<\/a>];
      push @arr, $file;
   }
   return unless $ses->{cq} eq $c->{$ses->{xq}};
   if($f->{link_rcpt}=~/^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/ && $#arr>-1)
   {
      my $tmpl = $ses->CreateTemplate("confirm_email_user.html");
      $tmpl->param('files' => \@arr);
      $ses->SendMail( $f->{link_rcpt}, $c->{email_from}, "$c->{site_name}: File send notification", $tmpl->output() );
   }
   if($c->{deurl_site} && $c->{deurl_api_key})
   {
      $features{has_deurl} = 1;
      require LWP::UserAgent;
      my $ua = LWP::UserAgent->new(timeout => 5);
      my $author = $ses->getUser ? $ses->getUser->{usr_login} : '';
      for(@arr)
      {
         my $res = $ua->post("$c->{deurl_site}/", 
                             {
                                op  => 'api',
                                api_key => $c->{deurl_api_key},
                                url => $_->{download_link},
                                size => sprintf("%.01f",$_->{file_size2}/1048576),
                                author => $author,
                             }
                            )->content;
         ($_->{deurl}) = $res=~/^OK:(.+)$/;
      }
   }
   if($ses->iPlg('c') && $c->{twit_enable_posting} && $ses->getUser)
   {
      my $data = $db->SelectARef("SELECT name,value FROM UserData WHERE usr_id=?",$ses->getUserId);
      my $udata;
      $udata->{$_->{name}}=$_->{value} for @$data;
      if($udata->{twitter_login} && $udata->{twitter_password})
      {
         require Net::Twitter::Lite::WithAPIv1_1;
         my $nt = Net::Twitter::Lite::WithAPIv1_1->new(consumer_key        => $c->{twit_consumer1},
                                          consumer_secret     => $c->{twit_consumer2},
                                          access_token        => $udata->{twitter_login},
                                          access_token_secret => $udata->{twitter_password},
                                         );
         for(@arr)
         {
            my $descr = substr($_->{file_descr},0,100);
            $descr="$descr " if $descr;
            $descr.="$_->{file_name} " if $udata->{twitter_filename};
            eval { $nt->update("$descr$_->{download_link}") };
            #die"Twitter error: $@" if $@;
         }
      }
   }

   if(-f "$c->{site_path}/catalogue.rss" && time-(lstat("$c->{site_path}/catalogue.rss"))[9]>3)
   {
     my $last = $db->SelectARef("SELECT file_code,file_name,file_descr,DATE_FORMAT(CONVERT_TZ(file_created, 'SYSTEM', '+0:00'),'%a, %d %b %Y %T GMT') as date FROM Files WHERE file_public=1 ORDER BY file_created DESC LIMIT 20");
     for (@$last)
     {
       $_->{download_link} = $ses->makeFileLink($_);
       $_->{download_link}=~s/\&/&amp;/gs;
       $_->{download_link}=$ses->SecureStr($_->{download_link});
       $_->{file_name}=~s/\&/&amp;/gs;
       $_->{file_name}=$ses->SecureStr($_->{file_name});
     }
     my $tt = $ses->CreateTemplate("feed.rss");
     $tt->param(list => $last);
     open FILE, ">$c->{site_path}/catalogue.rss";
     print FILE $tt->output;
     close FILE;
   }return unless $ses->{dc};

   $ses->ApplyPlugins('file_new',$_,$ses->db) for @arr;
   
   if($f->{ajax})
   {
      print "Content-type: text/html\n\nOK";
      return;
   }

   if($f->{box})
   {
      $ses->{form}->{no_hdr} = 1;
      return $ses->PrintTemplate('upload_results_box.html', 'links' => \@arr);
   }
   else
   {
	   return $ses->PrintTemplate("upload_results.html",
         'links' => \@arr,
         'successfull_count' => int(grep {! $_->{error}} @arr),
         %{features});
   }
}

sub AdminDownloads
{
   $f->{usr_id}=$db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{usr_login}) if $f->{usr_login};
   $f->{owner_id}=$db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{owner_login}) if $f->{owner_login};
   my $filter_user = "AND i.usr_id=$f->{usr_id}" if $f->{usr_id}=~/^\d+$/;
   my $filter_owner = "AND i.owner_id=$f->{owner_id}" if $f->{owner_id}=~/^\d+$/;
   my $filter_ip = "AND i.ip=INET_ATON('$f->{ip}')" if $f->{ip}=~/^[\d\.]+$/;
   my $filter_file = "AND f.file_id='$f->{file_id}'" if $f->{file_id}=~/^[\d\.]+$/;
   my $list = $db->SelectARef("SELECT i.*, INET_NTOA(i.ip) as ip, 
                                      f.file_name, f.file_code, i.finished, f.file_size,
                                      u.usr_login
                               FROM IP2Files i
                               LEFT JOIN Files f ON f.file_id=i.file_id
                               LEFT JOIN Users u ON i.usr_id = u.usr_id
                               WHERE i.file_id=f.file_id
                               $filter_user
                               $filter_owner
                               $filter_ip
                               $filter_file
                               ORDER BY created DESC".$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*)
                               FROM IP2Files i
                               LEFT JOIN Files f ON f.file_id=i.file_id
                               WHERE 1
                               $filter_user
                               $filter_owner
                               $filter_ip
                               $filter_file
                              ");
   my $gi;
   if($c->{admin_geoip} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
   }
   for(@$list)
   {
      $_->{download_link} = $ses->makeFileLink($_);

      $_->{money}= $_->{money} eq '0.0000' ? '' : "$c->{currency_symbol}$_->{money}";
      $_->{money}=~s/0+$//;
      $_->{percent} = min(100, int($_->{size} * 100 / $_->{file_size})) if $_->{file_size};
      $_->{referer} = $ses->SecureStr($_->{referer});
      if($gi)
      {
         $_->{ip_country} = $gi->country_code_by_addr($_->{ip});
      }
   }
   $ses->PrintTemplate("admin_downloads.html",
                       list      =>$list,
                       usr_login => $f->{usr_login},
                       ip        => $f->{ip},
                       paging    => $ses->makePagingLinks($f,$total),
                       m_n_100_complete => $c->{m_n_100_complete},
                      );
}

sub News
{
   my $news = $db->SelectARef("SELECT n.*, DATE_FORMAT(n.created,'%M %dth, %Y') as created_txt,
                                      COUNT(c.cmt_id) as comments
                               FROM News n
                               LEFT JOIN Comments c ON c.cmt_type=2 AND c.cmt_ext_id=n.news_id
                               WHERE n.created<=NOW()
                               GROUP BY n.news_id
                               ORDER BY n.created DESC".$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*) FROM News WHERE created<NOW()");
   for(@$news)
   {
      $_->{site_url} = $c->{site_url};
      $_->{news_text} =~s/\n/<br>/gs;
      $_->{enable_file_comments} = $c->{enable_file_comments};
   }
   $ses->PrintTemplate("news.html",
                       'news' => $news,
                       'paging' => $ses->makePagingLinks($f,$total),
                      );
}

sub NewsDetails
{
   my $news = $db->SelectRow("SELECT *, DATE_FORMAT(created,'%M %e, %Y at %r') as date 
                              FROM News 
                              WHERE news_id=? AND created<=NOW()",$f->{news_id});
   return $ses->message("No such news") unless $news;
   $news->{news_text} =~s/\n/<br>/gs;
   my $comments = &CommentsList(2,$f->{news_id});
   $ses->{page_title} = $ses->{meta_descr} = $news->{news_title};
   $ses->PrintTemplate("news_details.html",
                        %{$news},
                        'cmt_type'     => 2,
                        'cmt_ext_id'   => $news->{news_id},
                        'comments' => $comments,
                        'enable_file_comments' => $c->{enable_file_comments},
                        'token'      => $ses->genToken, # comments.html
                      );
}

sub CommentsList
{
   my ($cmt_type,$cmt_ext_id) = @_;
   my $list = $db->SelectARef("SELECT *, INET_NTOA(cmt_ip) as ip, DATE_FORMAT(created,'%M %e, %Y at %r') as date
                               FROM Comments 
                               WHERE cmt_type=? 
                               AND cmt_ext_id=?
                               ORDER BY created",$cmt_type,$cmt_ext_id);
   for (@$list)
   {
      $_->{cmt_text}=~s/\n/<br>/gs;
      $_->{cmt_name} = "<a href='$_->{cmt_website}'>$_->{cmt_name}</a>" if $_->{cmt_website};
      if($ses->getUser && $ses->getUser->{usr_adm})
      {
         $_->{email} = $_->{cmt_email};
         $_->{adm} = 1;
      }
   }
   return $list;
}

sub ChangeLanguage
{
   $ses->setCookie('lang',$f->{lang});
   return $ses->redirect($ENV{HTTP_REFERER}||$c->{site_url});
}

sub Page
{
   my $tmpl = shift || $f->{tmpl};
   $ses->{language}=$c->{default_language} unless -e "Templates/Pages/$ses->{language}/$tmpl.html";
   die("Templates/Pages/$ses->{language}/$tmpl.html") unless -e "Templates/Pages/$ses->{language}/$tmpl.html";
   $ses->PrintTemplate("Pages/$ses->{language}/$tmpl.html");
}

sub Contact
{
   $ses->setCaptchaMode($c->{captcha_mode}||2);
   my %secure = $ses->SecSave( 1, 2 );
   $f->{$_}=$ses->SecureStr($f->{$_}) for keys %$f;
   $f->{email}||=$ses->getUser->{usr_email} if $ses->getUser;
   $ses->PrintTemplate("contact.html",
                       %{$f},
                       %secure,
                      );
}

sub ContactSend
{
   $ses->setCaptchaMode($c->{captcha_mode}||2);
   return &Contact unless $ENV{REQUEST_METHOD} eq 'POST';
   return &Contact unless $ses->SecCheck( $f->{'rand'}, 1, $f->{code} );

   $f->{msg}.="Email is not valid. " unless $f->{email} =~ /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
   $f->{msg}.="Message required. " unless $f->{message};
   
   return &Contact if $f->{msg};

   $f->{$_}=$ses->SecureStr($f->{$_}) for keys %$f;

   $f->{message} = "You've got new message from $c->{site_name}.\n\nName: $f->{name}\nE-mail: $f->{email}\nIP: $ENV{REMOTE_ADDR}\n\n$f->{message}";
   $c->{email_text}=1;
   $ses->SendMail($c->{contact_email}, $c->{email_from}, "New message from $c->{site_name} contact form", $f->{message});
   return $ses->redirect("$c->{site_url}/?msg=Message sent successfully");
}

sub DelFile
{
   my ($id,$del_id) = @_;
   $id||=$f->{id};
   $del_id||=$f->{del_id};
   my $file = $db->SelectRow("SELECT * FROM Files f, Servers s
                              WHERE file_code=?
                              AND f.srv_id=s.srv_id",$id);
   return $ses->message('No such file exist') unless $file;
   return $ses->message('Server with this file is Offline') if $file->{srv_status} eq 'OFF';

   unless($file->{file_del_id} eq $del_id)
   {
      return $ses->message('Wrong Delete ID')
   }
   if($f->{confirm} eq 'yes')
   {
      $ses->DeleteFile($file);
      $ses->PrintTemplate("delete_file.html",
         'token'      => $ses->genToken,
         'status'=>$ses->{lang}->{lang_file_deleted});
   }
   else
   {
      $ses->PrintTemplate("delete_file.html",
                          'confirm' =>1,
                          'id'      => $id,
                          'del_id'  => $del_id,
                          'fname'   => $file->{file_name},
                         );
   }
}

sub TrashFiles
{
   return if !@_;
   return $ses->DeleteFilesMass(\@_) if !$c->{trash_expire};
   my $file_ids = join(",", map { $_->{file_id} } @_);
   $db->Exec("UPDATE Files SET file_trashed=NOW() WHERE file_id IN ($file_ids)");

   if($c->{memcached_location})
   {
      $db->Uncache( 'file', $db->SelectOne("SELECT file_code FROM Files WHERE file_id=?", $_->{file_id} ) ) for @_;
   }
}

sub TrashFolder
{
   my ($fld_id) = @_;
   return $db->Exec("DELETE FROM Folders WHERE fld_id=?", $fld_id) if !$c->{trash_expire};
   $db->Exec("UPDATE Folders SET fld_trashed=1 WHERE fld_id=?", $fld_id);
}

sub UntrashFiles
{
   my (@files) = @_;
   for my $file (@files)
   {
	   $db->Exec("UPDATE Files SET file_trashed=0 WHERE file_id=?", $file->{file_id});

      # Traversing folders tree until root
      my $folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=?", $file->{file_fld_id});
	   while($folder)
      {
         $db->Exec("UPDATE Folders SET fld_trashed=0 WHERE fld_id=?", $folder->{fld_id});
         $folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=?", $folder->{fld_parent_id});
      }
   }
}

sub AdminFiles
{
   if($ses->checkToken)
   {
      if($f->{del_code})
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         my $file = $db->SelectRow("SELECT f.*, u.usr_aff_id
                                    FROM Files f 
                                    LEFT JOIN Users u ON f.usr_id=u.usr_id
                                    WHERE file_code=?",$f->{del_code});
         return $ses->message("No such file") unless $file;
         $file->{del_money}=$c->{del_money_file_del};
         $ses->DeleteFile($file);
         if($f->{del_info})
         {
            $db->Exec("INSERT INTO DelReasons SET file_code=?, file_name=?, info=?",$file->{file_code},$file->{file_name},$f->{del_info});
         }
         return $ses->redirect("$c->{site_url}/?op=admin_files");
      }
      if($f->{del_selected} && $f->{file_id})
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         die"security error" unless $ENV{REQUEST_METHOD} eq 'POST';
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
         return $ses->redirect($c->{site_url}) unless $ids;
         my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)");
         $_->{del_money}=$c->{del_money_file_del} for @$files;
         $ses->DeleteFilesMass($files);
         if($f->{del_info})
         {
            for(@$files)
            {
               $db->Exec("INSERT INTO DelReasons SET file_code=?, file_name=?, info=?",$_->{file_code},$_->{file_name},$f->{del_info});
            }
         }
         
         return $ses->redirect("$c->{site_url}/?op=admin_files");
      }
      if($f->{transfer_files} && $f->{srv_id2} && $f->{file_id})
      {
         return &AdminServersTransfer;
      }
      if($f->{reencode_selected} || $f->{rethumb_selected})
      {
         my ($op) = grep { s/_selected$// } keys(%$f);
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
         return $ses->redirect($c->{site_url}) unless $ids;

         my (@subset, %group);
         my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)");
         @subset = grep { $_->{file_name} =~ /\.(avi|divx|flv|mp4|wmv|mkv)$/i } @$files if $op eq 'reencode';
         @subset = grep { $_->{file_name} =~ /\.(jpg|jpeg|gif|png|bmp)$/i } @$files if $op eq 'rethumb';
         $_->{dx} = sprintf("%05d", ($_->{file_real_id}||$_->{file_id}) / $c->{files_per_folder}) for @subset;
         $group{$_->{srv_id}} = $_ for @subset;

         for my $srv_id (keys %group)
         {
            my $res = $ses->api2($srv_id,
            {
               op => $op,
               list => join("\n", map { "$_->{dx}:$_->{file_real}" } @subset),
               file_names => join("\n", map { $_->{file_name} } @subset),
            }); 
            $ses->message("Error occured: $res") if $res !~ /^OK/;
         }
      }
   }

   my $filter_files;
   $f->{mass_search}=~s/\r//gs;
   $f->{mass_search}=~s/\s+\n/\n/gs;
   if($f->{mass_search})
   {
      my @arr;
      push @arr,$1 while $f->{mass_search}=~/\/(\w{12})(\/|\n|$)/gs;
      $filter_files = "AND file_code IN ('".join("','",@arr)."')";
   }

   $f->{sort_field}||='file_created';
   $f->{sort_order}||='down';
   $f->{per_page}||=$c->{items_per_page};
   $f->{usr_id}=$db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{usr_login}) if $f->{usr_login};
   my $filter_key    = "AND (file_name LIKE '%$f->{key}%' OR file_code='$f->{key}')" if $f->{key};
   my $filter_user   = "AND f.usr_id='$f->{usr_id}'" if $f->{usr_id}=~/^\d+$/;
   my $filter_server = "AND f.srv_id='$f->{srv_id}'" if $f->{srv_id}=~/^\d+$/;
   my $filter_down_more = "AND f.file_downloads>$f->{down_more}" if $f->{down_more}=~/^\d+$/;
   my $filter_down_less = "AND f.file_downloads<$f->{down_less}" if $f->{down_less}=~/^\d+$/;
   my $filter_size_more = "AND f.file_size>".$f->{size_more}*1048576 if $f->{size_more}=~/^[\d\.]+$/;
   my $filter_size_less = "AND f.file_size<".$f->{size_less}*1048576 if $f->{size_less}=~/^[\d\.]+$/;
   my $filter_file_real = "AND f.file_real='$f->{file_real}'" if $f->{file_real}=~/^\w{12}$/;

   my $filter_ip     = "AND f.file_ip=INET_ATON('$f->{ip}')" if $f->{ip}=~/^\d+\.\d+\.\d+\.\d+$/;
   my $files = $db->SelectARef("SELECT f.*, file_downloads*file_size as traffic,
                                       INET_NTOA(file_ip) as file_ip,
                                       u.usr_id, u.usr_login
                                FROM Files f
                                LEFT JOIN Users u ON f.usr_id = u.usr_id
                                WHERE 1
                                $filter_files
                                $filter_key
                                $filter_user
                                $filter_server
                                $filter_down_more
                                $filter_down_less
                                $filter_size_more
                                $filter_size_less
                                $filter_ip
                                $filter_file_real
                                ".&makeSortSQLcode($f,'file_created').$ses->makePagingSQLSuffix($f->{page},$f->{per_page}) );
   my $total = $db->SelectOne("SELECT COUNT(*) as total_count
                                FROM Files f 
                                WHERE 1 
                                $filter_files
                                $filter_key 
                                $filter_user 
                                $filter_server
                                $filter_down_more
                                $filter_down_less
                                $filter_size_more
                                $filter_size_less
                                $filter_ip
                                $filter_file_real
                                ");

   my $gi;
   if($c->{admin_geoip} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
   }
         
   for(@$files)
   {
      $_->{site_url} = $c->{site_url};
      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = length($file_name)>$c->{display_max_filename} ? substr($file_name,0,$c->{display_max_filename}).'&#133;' : $file_name;
      utf8::encode($_->{file_name_txt});
      $_->{file_size2} = $ses->makeFileSize($_->{file_size});
      $_->{traffic}    = $_->{traffic} ? $ses->makeFileSize($_->{traffic}) : '';
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_downloads}||='';
      $_->{file_last_download}='' unless $_->{file_downloads};
      $_->{file_money} = $_->{file_money} eq '0.0000' ? '' : ($c->{currency_symbol}||'$').$_->{file_money};
      if($gi)
      {
          $_->{file_country} = $gi->country_code_by_addr($_->{file_ip});
      }
   }
   my %sort_hash = &makeSortHash($f,['file_name','usr_login','file_downloads','file_money','file_size','traffic','file_created','file_last_download']);

   my $servers = $db->SelectARef("SELECT srv_id,srv_name FROM Servers WHERE srv_status<>'OFF' ORDER BY srv_id");
   
   $ses->PrintTemplate("admin_files.html",
                       'files'   => $files,
                       'key'     => $f->{key},
                       'usr_id'  => $f->{usr_id},
                       'srv_id'  => $f->{srv_id},
                       'down_more'  => $f->{down_more},
                       'down_less'  => $f->{down_less},
                       'size_more'  => $f->{size_more},
                       'size_less'  => $f->{size_less},
                       "per_$f->{per_page}" => ' checked',
                       %sort_hash,
                       'paging'     => $ses->makePagingLinks($f,$total),
                       'items_per_page' => $c->{items_per_page},
                       'servers'    => $servers,
                       'usr_login'  => $f->{usr_login},
                       'token'      => $ses->genToken,
                       'm_v'        => $c->{m_v},
                       'm_i'        => $c->{m_i},
                      );
}

sub ModeratorFiles
{
   return $ses->message("Access denied") if !$ses->getUser->{usr_adm} && !($c->{m_d} && $ses->getUser->{usr_mod} && $c->{m_d_f});
   if($f->{del_selected} && $f->{file_id})
   {
      return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
      my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
      return $ses->redirect($c->{site_url}) unless $ids;
      my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)");
      $_->{del_money}=$c->{del_money_file_del} for @$files;
      $ses->DeleteFilesMass($files);
      if($f->{del_info})
      {
         for(@$files)
         {
            $db->Exec("INSERT INTO DelReasons SET file_code=?, file_name=?, info=?",$_->{file_code},$_->{file_name},$f->{del_info});
         }
      }
      return $ses->redirect("$c->{site_url}/?op=moderator_files");
   }

   my $filter_files;
   if($f->{mass_search})
   {
      my @arr;
      push @arr,$1 while $f->{mass_search}=~/\/(\w{12})\//gs;
      $filter_files = "AND file_code IN ('".join("','",@arr)."')";
   }

   $f->{per_page}||=$c->{items_per_page};
   $f->{usr_id}=$db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{usr_login}) if $f->{usr_login};
   my $filter_key    = "AND (file_name LIKE '%$f->{key}%' OR file_code='$f->{key}')" if $f->{key};
   my $filter_user   = "AND f.usr_id='$f->{usr_id}'" if $f->{usr_id};
   my $filter_ip     = "AND f.file_ip=INET_ATON('$f->{ip}')" if $f->{ip}=~/^[\d\.]+$/;
   my $files = $db->SelectARef("SELECT f.*,
                                       INET_NTOA(file_ip) as file_ip,
                                       u.usr_id, u.usr_login
                                FROM Files f
                                LEFT JOIN Users u ON f.usr_id = u.usr_id
                                WHERE 1
                                $filter_files
                                $filter_key
                                $filter_user
                                $filter_ip
                                ORDER BY file_created DESC
                                ".$ses->makePagingSQLSuffix($f->{page},$f->{per_page}) );
   my $total = $db->SelectOne("SELECT COUNT(*) as total_count
                                FROM Files f 
                                WHERE 1 
                                $filter_files
                                $filter_key 
                                $filter_user 
                                $filter_ip
                                ");

   for(@$files)
   {
      $_->{site_url} = $c->{site_url};
      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = length($file_name)>$c->{display_max_filename} ? substr($file_name,0,$c->{display_max_filename}).'&#133;' : $file_name;
      utf8::encode($_->{file_name_txt});
      $_->{file_size2} = sprintf("%.01f Mb",$_->{file_size}/1048576);
      $_->{download_link} = $ses->makeFileLink($_);
   }
  
   $ses->PrintTemplate("admin_files_moderator.html",
                       'files'   => $files,
                       'key'     => $f->{key},
                       'usr_id'  => $f->{usr_id},
                       "per_$f->{per_page}" => ' checked',
                       'paging'     => $ses->makePagingLinks($f,$total),
                       'items_per_page' => $c->{items_per_page},
                       'usr_login'  => $f->{usr_login},
                       'token'      => $ses->genToken,
                      );
}

sub AdminUsers
{
   if($ses->checkToken)
   {
      if($f->{del_id})
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=?",$f->{del_id});
   
         $ses->DeleteFilesMass($files);
         $ses->DeleteUserDB($f->{del_id});
         return $ses->redirect("?op=admin_users");
      }
      if($f->{del_pending}=~/^\d+$/)
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         my $users = $db->SelectARef("SELECT * FROM Users WHERE usr_status='PENDING' AND usr_created<CURDATE()-INTERVAL ? DAY",$f->{del_pending});
         for my $user (@$users)
         {
            my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=?",$user->{usr_id});
            $ses->DeleteFilesMass($files);
            $ses->DeleteUserDB($user->{usr_id});
         }
         return $ses->redirect_msg("?op=admin_users","Deleted users: ".($#$users+1));
      }
      if($f->{del_inactive}=~/^\d+$/)
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         my $users = $db->SelectARef("SELECT * FROM Users 
                                      WHERE usr_created<CURDATE()-INTERVAL ? DAY 
                                      AND usr_lastlogin<CURDATE() - INTERVAL ? DAY",$f->{del_inactive},$f->{del_inactive});
         for my $user (@$users)
         {
            my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=?",$user->{usr_id});
            $ses->DeleteFilesMass($files);
            $ses->DeleteUserDB($user->{usr_id});
         }
         return $ses->redirect_msg("?op=admin_users","Deleted users: ".($#$users+1));
      }
      if($f->{del_users} && $f->{usr_id})
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{usr_id})});
         return $ses->redirect($c->{site_url}) unless $ids;
         my $users = $db->SelectARef("SELECT * FROM Users WHERE usr_id IN ($ids)");
         for my $user (@$users)
         {
            my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=?",$user->{usr_id});
            $ses->DeleteFilesMass($files);
            $ses->DeleteUserDB($user->{usr_id});
         }
         return $ses->redirect("?op=admin_users");
      }
   }
   if($f->{extend_premium_all})
   {
      return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
      $db->Exec("UPDATE Users SET usr_premium_expire=usr_premium_expire + INTERVAL ? DAY WHERE usr_premium_expire>=NOW()",$f->{extend_premium_all});
      return $ses->redirect("?op=admin_users");
   }
   if($f->{resend_activation})
   {
      my $user = $db->SelectRow("SELECT usr_id,usr_login FROM Users WHERE usr_id=?",$f->{resend_activation});
      $f->{d} = "$user->{usr_id}-$user->{usr_login}";
      &ResendActivationCode(1);
   }
   if($f->{activate})
   {
      $db->Exec("UPDATE Users SET usr_status='OK', usr_security_lock='' WHERE usr_id=?",$f->{activate});
      return $ses->redirect_msg("?op=admin_users","User activated");
   }
   if($f->{mass_email} && $f->{usr_id})
   {
      &AdminMassEmail;
   }

   $f->{sort_field}||='usr_created';
   $f->{sort_order}||='down';
   my $filter_key = "AND (usr_login LIKE '%$f->{key}%' OR usr_email LIKE '%$f->{key}%')" if $f->{key};
   $filter_key = "AND usr_lastip=INET_ATON('$f->{key}')" if $f->{key}=~/^\d+\.\d+\.\d+\.\d+$/;
   my $filter_prem= "AND usr_premium_expire>NOW()" if $f->{premium_only};
   my $filter_money= "AND usr_money>=$f->{money}" if $f->{money}=~/^[\d\.]+$/;
   my $users = $db->SelectARef("SELECT u.*,
                                       INET_NTOA(usr_lastip) as usr_ip,
                                       COUNT(f.file_id) as files,
                                       SUM(f.file_size) as disk_used,
                                       UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec,
                                       TO_DAYS(CURDATE())-TO_DAYS(usr_lastlogin) as last_visit
                                FROM Users u
                                LEFT JOIN Files f ON u.usr_id = f.usr_id
                                WHERE 1
                                $filter_key
                                $filter_prem
                                $filter_money
                                GROUP BY usr_id
                                ".&makeSortSQLcode($f,'usr_created').$ses->makePagingSQLSuffix($f->{page}) );
   my $totals = $db->SelectRow("SELECT COUNT(*) as total_count
                                FROM Users f WHERE 1 
                                $filter_key 
                                $filter_prem
                                $filter_money");

   my $gi;
   if($c->{admin_geoip} && -f "$c->{cgi_path}/GeoIP.dat")
   {
      require Geo::IP;
      $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
   }

   for(@$users)
   {
      $_->{site_url} = $c->{site_url};
      $_->{disk_used} = $_->{disk_used} ? $ses->makeFileSize($_->{disk_used}) : '';
      $_->{premium} = $_->{exp_sec}>0;
      $_->{last_visit} = defined $_->{last_visit} ? "$_->{last_visit} $ses->{lang}->{lang_days_ago}" : $ses->{lang}->{lang_never};
      substr($_->{usr_created},-3)='';
      $_->{"status_$_->{usr_status}"}=1;
      $_->{usr_money} = $_->{usr_money}=~/^[0\.]+$/ ? '' : ($c->{currency_symbol}||'$').$_->{usr_money};
      $_->{usr_country} = $gi->country_code_by_addr($_->{usr_ip}) if $gi;
   }
   my %sort_hash = &makeSortHash($f,['usr_login','usr_email','files','usr_created','disk_used','last_visit','usr_money']);
   
   $ses->PrintTemplate("admin_users.html",
                       'users'  => $users,
                       %{$totals},
                       'key'    => $f->{key},
                       'premium_only' => $f->{premium_only},
                       'money' => $f->{money},
                       %sort_hash,
                       'paging' => $ses->makePagingLinks($f,$totals->{total_count}),
                       'token'  => $ses->genToken,
                      );
}

sub AdminUserEdit
{
    if($f->{save} && $ENV{REQUEST_METHOD} eq 'POST' && $ses->checkToken)
    {
       return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
       $db->Exec("UPDATE Users 
                  SET usr_login=?, 
                      usr_email=?, 
                      usr_premium_expire=?, 
                      usr_status=?, 
                      usr_money=?,
                      usr_disk_space=?,
                      usr_bw_limit=?,
                      usr_up_limit=?,
                      usr_mod=?,
                      usr_aff_id=?,
                      usr_notes=?,
                      usr_reseller=?,
                      usr_profit_mode=?,
                      usr_max_rs_leech=?,
                      usr_aff_enabled=?,
                      usr_dmca_agent=?,
                      usr_sales_percent=?,
                      usr_rebills_percent=?,
                      usr_m_x_percent=?
                  WHERE usr_id=?",
                  $f->{usr_login},
                  $f->{usr_email},
                  $f->{usr_premium_expire},
                  $f->{usr_status},
                  $f->{usr_money},
                  $f->{usr_disk_space},
                  $f->{usr_bw_limit},
                  $f->{usr_up_limit},
                  $f->{usr_mod},
                  $f->{usr_aff_id},
                  $f->{usr_notes},
                  $f->{usr_reseller},
                  $f->{usr_profit_mode}||'PPD',
                  $f->{usr_max_rs_leech}||'',
                  $f->{usr_aff_enabled}||0,
                  $f->{usr_dmca_agent}||0,
                  $f->{usr_sales_percent}||0,
                  $f->{usr_rebills_percent}||0,
                  $f->{usr_m_x_percent}||0,
                  $f->{usr_id}
                 );
       $db->Exec("UPDATE Users SET usr_password=? WHERE usr_id=?",XUtils::GenPasswdHash($f->{usr_password}),$f->{usr_id}) if $f->{usr_password};
       return $ses->redirect("?op=admin_user_edit&usr_id=$f->{usr_id}");
    }
    if($f->{ref_del})
    {
       $db->Exec("UPDATE Users SET usr_aff_id=0 WHERE usr_id=?",$f->{ref_del});
       return $ses->redirect("?op=admin_user_edit&usr_id=$f->{usr_id}");
    }
    my $user = $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec FROM Users WHERE usr_id=?
                              ",$f->{usr_id});
    my $transactions = $db->SelectARef("SELECT * FROM Transactions WHERE usr_id=? AND verified=1 ORDER BY created DESC",$f->{usr_id});
    $_->{site_url}=$c->{site_url} for @$transactions;

    my $payments = $db->SelectARef("SELECT * FROM Payments WHERE usr_id=? ORDER BY created DESC",$f->{usr_id});

    my $referrals = $db->SelectARef("SELECT usr_id,usr_login,usr_created,usr_money,usr_aff_id 
                                     FROM Users 
                                     WHERE usr_aff_id=? 
                                     ORDER BY usr_created DESC 
                                     LIMIT 11",$f->{usr_id});
    $referrals->[10]->{more}=1 if $#$referrals>9;

    my $files_num = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE usr_id=?",$user->{usr_id});
    
    require Time::Elapsed;
    my $et  = new Time::Elapsed;
    $ses->PrintTemplate("admin_user_form.html",
                        %{$user},
                        usr_id1 => $user->{usr_id},
                        expire_elapsed => $user->{exp_sec}>0 ? $et->convert($user->{exp_sec}) : '',
                        transactions   => $transactions,
                        payments       => $payments,
                        "status_$user->{usr_status}" => ' selected',
                        referrals      => $referrals,
                        m_d            => $c->{m_d},
                        m_k_manual     => $c->{m_k} && $c->{m_k_manual},
                        m_y            => $ses->iPlg('p'),
                        bw_limit_days  => $c->{bw_limit_days},
                        up_limit_days  => $c->{up_limit_days},
                        "usr_profit_mode_$user->{usr_profit_mode}" => ' selected',
                        files_num      => $files_num,
                       token      => $ses->genToken,
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                       enp_p             => $ses->iPlg('p'),
                       );
}

sub AdminUserReferrals
{
   my $referrals = $db->SelectARef("SELECT usr_id,usr_login,usr_created,usr_money,usr_aff_id 
                                     FROM Users 
                                     WHERE usr_aff_id=? 
                                     ORDER BY usr_created DESC 
                                     ".$ses->makePagingSQLSuffix($f->{page}),$f->{usr_id});
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Users WHERE usr_aff_id=?",$f->{usr_id});
   my $user = $db->SelectRow("SELECT usr_id,usr_login FROM Users WHERE usr_id=?",$f->{usr_id});
   $ses->PrintTemplate("admin_user_referrals.html",
                       referrals  => $referrals,
                       'paging' => $ses->makePagingLinks($f,$total),
                       %{$user},
                      );
}

sub AdminTorrents
{
   if($f->{del_torrent})
   {
      my $torr = $db->SelectRow("SELECT * FROM Torrents WHERE sid=?",$f->{del_torrent});
      return $ses->redirect("$c->{site_url}/?op=admin_torrents") unless $torr;

      my $res = $ses->api2($torr->{srv_id},{
                                  op   => 'torrent_delete',
                                  sid  => $f->{del_torrent},
                                 });

      return $ses->message("Error1:$res") unless $res eq 'OK';

      $db->Exec("DELETE FROM Torrents WHERE sid=? AND status='WORKING'",$f->{del_torrent});
      return $ses->redirect("$c->{site_url}/?op=admin_torrents")
   }
   if($f->{'kill'})
   {
      $ses->api2($f->{srv_id},{op => 'torrent_kill'});
      return $ses->redirect("$c->{site_url}/?op=admin_torrents");
   }

   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_torrent=1");
   for(@$servers)
   {
      my $res = $ses->api2($_->{srv_id},{ op => 'torrent_status' });
      #die $res;
      $_->{active}=1 if $res eq 'ON';
   }

   my $torrents = &getTorrents();

   my $webseed = $db->SelectARef("SELECT *, u.usr_login, f.srv_id, INET_NTOA(ip) AS ip2
      FROM BtTracker t
      LEFT JOIN Users u ON u.usr_id = t.usr_id
      LEFT JOIN Files f ON f.file_id = t.file_id
      WHERE last_announce > NOW() - INTERVAL 1 HOUR");
   for(@$webseed)
   {
      my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?", $_->{file_id});
      next if !$file;

      $_->{file_name} = $file->{file_name};
      $_->{download_link} = $ses->makeFileLink($file);
      $_->{finished} = 1 if $_->{bytes_left} == 0;
      $_->{progress} = int(100 * ($file->{file_size} - $_->{bytes_left}) / $file->{file_size}) . '%';
   }

   $ses->PrintTemplate("admin_torrents.html",
                       torrents  => $torrents,
                       servers   => $servers,
                       webseed   => $webseed,
                      );
}

sub AdminServers
{
   return AdminCheckDBFile() if $f->{admin_check_db_file};
   return AdminCheckFileDB() if $f->{admin_check_file_db};
   return AdminUpdateServerStats() if $f->{admin_update_srv_stats};

   my $servers = $db->SelectARef("SELECT s.*
                                  FROM Servers s
                                  ORDER BY srv_created
                                 ");
   for(@$servers)
   {
      $_->{srv_disk_percent} = sprintf("%.01f",100*$_->{srv_disk}/$_->{srv_disk_max}) if $_->{srv_disk_max};
      $_->{srv_disk} = sprintf("%.01f",$_->{srv_disk}/1073741824);
      $_->{srv_disk_max} = int $_->{srv_disk_max}/1073741824;
      my @a;
      push @a,"Regular" if $_->{srv_allow_regular};
      push @a,"Premium" if $_->{srv_allow_premium};
      $_->{user_types} = join '<br>', @a;
      $_->{lc($_->{srv_status})} = 1;
      $_->{not_off} = 1 if $_->{srv_status} ne 'OFF';
   }
   $ses->PrintTemplate("admin_servers.html",
                       'servers'  => $servers,
                      );
}

sub AdminServerAdd
{
   my %opts = @_;
   return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
   my $server;
   if($f->{srv_id})
   {
      $server = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?",$f->{srv_id});
      $server->{srv_disk_max}/=1024*1024*1024;
      $server->{"s_$server->{srv_status}"}=' selected';
   }
   elsif(!$db->SelectOne("SELECT srv_id FROM Servers LIMIT 1"))
   {
      $server->{srv_cgi_url}    = $c->{site_cgi};
      $server->{srv_htdocs_url} = "$c->{site_url}/files";
   }
   $server->{srv_allow_regular}=$server->{srv_allow_premium}=1 unless $f->{srv_id};
   $server->{srv_cdn} ||= $f->{srv_cdn}||$f->{cdn};

   if($server->{srv_cdn})
   {
      my @cdn_list = grep { $_->{listed} } (map { $_->options() } $ses->getPlugins('CDN'));
      my ($cdn) = grep { $_->{name} eq $server->{srv_cdn} } @cdn_list;
      $cdn ||= $cdn_list[0];
      $cdn->{selected} = 1 if $cdn;
      return $ses->message("Couldn't find appropriate plugin") if !$cdn;
      my $srv_data = $ses->getSrvData($server->{srv_id});
      $_->{value} = $f->{$_->{name}} || $srv_data->{$_->{name}} for(@{$cdn->{s_fields}});
      return $ses->PrintTemplate("admin_cdn_form.html",
                       %{$server},
                       %{$f},
                       tests => $opts{tests}||[],
                       cdn_list => \@cdn_list,
                       s_fields => $cdn->{s_fields},
                       srv_name => $cdn->{title},
                       'token'      => $ses->genToken(op => 'admin_server_save'),
                       );
   }

   return $ses->PrintTemplate("admin_server_form.html",
                       %{$server},
                       %{$f},
                       'tests' => $opts{tests}||[],
                       'ftp_mod' => $c->{ftp_mod},
                       'mmtt' => $ses->iPlg('t'),
                       'm_g'  => $ses->iPlg('g'),
                       'm_v'  => $c->{m_v},
                       'token'      => $ses->genToken(op => 'admin_server_save'),
                      );
}

sub AdminServerSave
{
   return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
   return $ses->message("Invalid token") if !$ses->checkToken();

   $f->{srv_cgi_url}=~s/\/$//;
   $f->{srv_htdocs_url}=~s/\/$//;
   return $ses->message("Server with same cgi-bin URL / htdocs URL already exist in DB") if !$f->{srv_id} && $db->SelectOne("SELECT srv_id FROM Servers WHERE srv_cgi_url=? OR srv_htdocs_url=?",$f->{srv_cgi_url},$f->{srv_htdocs_url});

   $f->{srv_allow_regular}||=0;
   $f->{srv_allow_premium}||=0;
   $f->{srv_torrent}||=0;
   $f->{srv_countries}||='';

   my @sflds = qw(srv_name srv_ip srv_cgi_url srv_htdocs_url srv_disk_max srv_status srv_key srv_allow_regular srv_allow_premium srv_torrent srv_countries srv_cdn srv_ftp);
   $f->{srv_disk_max}*=1024*1024*1024;
   if($f->{srv_id})
   {
      my @dat = map{$f->{$_}||''}@sflds;
      push @dat, $f->{srv_id};
      $db->Exec("UPDATE Servers SET ".join(',',map{"$_=?"}@sflds)." WHERE srv_id=?", @dat );
      $c->{srv_status} = $f->{srv_status};
      my $data = join('~',map{"$_:$c->{$_}"}qw(site_url site_cgi max_upload_files max_upload_filesize ip_not_allowed srv_status srv_countries));
      $ses->api2($f->{srv_id},{op=>'update_conf',data=>$data});
   }

   my ($cdn) = grep { $_->{name} eq $f->{srv_cdn} } $ses->getPlugins('CDN')->options if $f->{srv_cdn};
   my %srv_data = map { $_->{name} => $f->{$_->{name}} } @{$cdn->{s_fields}};
   $ses->setSrvData($f->{srv_id}, %srv_data) if $f->{srv_id};

   my @tests = $ses->getPlugins('CDN')->runTests($f);
   my $err_count = grep { /ERROR/ } @tests;
   my @arr = map { { 'text' => $_, 'class'=> /ERROR/ ? 'err' : 'ok' } } @tests;

   if($err_count)
   {
      $f->{srv_disk_max}/=1024*1024*1024;
      return &AdminServerAdd(tests => \@arr);
   }

   unless($f->{srv_id})
   {
      $f->{srv_key} = $c->{fs_key} = $ses->randchar(8);
      $c->{srv_status} = $f->{srv_status};
      $db->Exec("INSERT INTO Servers SET srv_created=CURDATE(), ".join(',',map{"$_=?"}@sflds), map{$f->{$_}||''}@sflds );
      my $srv_id = $db->getLastInsertId;
      my $data = join('~',map{"$_:$c->{$_}"}qw(fs_key dl_key site_url site_cgi max_upload_files max_upload_filesize ext_allowed ext_not_allowed ip_not_allowed srv_status));
      my %srv_data = map { $_->{name} => $f->{$_->{name}} } @{$cdn->{s_fields}};
      $ses->setSrvData($srv_id, %srv_data);
      my $res = $ses->api($f->{srv_cgi_url},{op=>'update_conf',data=>$data}) if !$f->{srv_cdn};
      return $ses->message("Server created. But was unable to update FS config.<br>Probably fs_key was not empty. Update fs_key manually and save Site Settings to sync.($res)") if $res && $res ne'OK';
   }

   return $ses->redirect('?op=admin_servers');
}

sub AdminServersTransfer
{
   $f->{files_num}=5000 if $f->{file_id};
   return $ses->message("Number of files required!") unless $f->{files_num};
   my $order="file_size DESC" if $f->{order} eq 'size_desc';
   $order="file_size" if $f->{order} eq 'size_enc';
   $order="file_id DESC" if $f->{order} eq 'id_desc';
   $order="file_id" if $f->{order} eq 'id_enc';
   $order||='file_id';
   $f->{files_num}=~s/\D//g;
   my $filter_downloads1="AND file_downloads>$f->{filter_downloads_more}" if $f->{filter_downloads_more}=~/^\d+$/;
   my $filter_downloads2="AND file_downloads<$f->{filter_downloads_less}" if $f->{filter_downloads_less}=~/^\d+$/;
   my $filter_files="AND file_id IN (".join(',',@{ARef($f->{file_id})}).")" if $f->{file_id};
   my $filter_server="AND srv_id=$f->{srv_id1}" if $f->{srv_id1}=~/^\d+$/ && !$filter_files;
   my $files = $db->SelectARef("SELECT *
                                FROM Files
                                WHERE srv_id!=?
                                $filter_server
                                $filter_downloads1
                                $filter_downloads2
                                $filter_files
                                GROUP BY file_real
                                ORDER BY $order
                                LIMIT $f->{files_num}",$f->{srv_id2});
   for my $ff (@$files)
   {
      $db->Exec("DELETE FROM QueueTransfer WHERE file_real=? LIMIT 50", $ff->{file_real} );
      $db->Exec("INSERT IGNORE INTO QueueTransfer
                 SET file_real=?, 
                     file_id=?,
                     srv_id1=?,
                     srv_id2=?,
                     created=NOW()", $ff->{file_real}, 
                                     $ff->{file_id}, 
                                     $ff->{srv_id},
                                     $f->{srv_id2}
                                      ) if $ff->{srv_id}!=$f->{srv_id2};
   }
   return $ses->redirect_msg("?op=admin_servers",($#$files+1)." files were moved to Transfer Queue");
}

sub AdminTransferList
{
   if($f->{del_id} && $ses->checkToken)
   {
      $db->Exec("DELETE FROM QueueTransfer WHERE file_real=? LIMIT 1",$f->{del_id});
      return $ses->redirect('?op=admin_transfer_list');
   }
   if($f->{restart} && $ses->checkToken)
   {
      $db->Exec("UPDATE QueueTransfer SET status='PENDING', error='' WHERE file_real=? LIMIT 1",$f->{restart});
      return $ses->redirect('?op=admin_transfer_list');
   }
   if($f->{del_all} && $ses->checkToken)
   {
      $db->Exec("DELETE FROM QueueTransfer");
      return $ses->redirect('?op=admin_transfer_list');
   }
   if($f->{restart_all} && $ses->checkToken)
   {
      $db->Exec("UPDATE QueueTransfer SET status='PENDING', error=''");
      return $ses->redirect('?op=admin_transfer_list');
   }
   my $list = $db->SelectARef("SELECT q.*, f.*,
                                      UNIX_TIMESTAMP()-UNIX_TIMESTAMP(q.created) as created2,
                                      UNIX_TIMESTAMP()-UNIX_TIMESTAMP(q.updated) as dt,
                                      s1.srv_name as srv_name1, s2.srv_name as srv_name2
                               FROM QueueTransfer q, Files f, Servers s1, Servers s2
                               WHERE q.file_id=f.file_id
                               AND q.srv_id1=s1.srv_id
                               AND q.srv_id2=s2.srv_id
                               ORDER BY started DESC, created
                               LIMIT 1000
                              ");
   my @stucked;
   for(@$list)
   {
      $_->{site_url} = $c->{site_url};
      my $file_title = $_->{file_title}||$_->{file_name};
      utf8::decode($file_title);
      $_->{file_title_txt} = length($file_title)>$c->{display_max_filename_admin} ? substr($file_title,0,$c->{display_max_filename_admin}).'&#133;' : $file_title;
      utf8::encode($_->{file_title_txt});
      
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{qstatus}=" <i style='color:green;'>[moving]</i>" if $_->{status} eq 'MOVING';
      if( $_->{status} eq 'MOVING' && $_->{dt}>30 )
      {
         push @stucked, $_->{file_real};
         $_->{qstatus}=" <i style='color:#c66;'>[stuck]</i> <a href='?op=admin_transfer_list&restart=$_->{file_real}'>[restart]</a>";
      }
      if( $_->{status}=~/^(ERROR|MOVING)$/ && $_->{error} )
      {
         push @stucked, $_->{file_real};
         $_->{qstatus}=qq[ <a href="#" onclick="\$('#err$_->{file_real_id}').toggle();return false;"><i style="color:#e66;">[error]</i></a><div id='err$_->{file_real_id}' style='display:none'>$_->{error}</div>
                           <a href='?op=admin_transfer_list&restart=$_->{file_real}'>[restart]</a>];
      }
      
      $_->{created2} = $_->{created2}<60 ? "$_->{created2} secs" : ($_->{created2}<7200 ? sprintf("%.0f",$_->{created2}/60).' mins' : sprintf("%.0f",$_->{created2}/3600).' hours');
      $_->{created2}.=' ago';
      $_->{started2}='' if $_->{started} eq '0000-00-00 00:00:00';
      
      $_->{progress} = sprintf("%.0f", 100*$_->{transferred}/$_->{file_size} ) if $_->{file_size};
      $_->{file_size} = sprintf("%.0f MB",$_->{file_size}/1024/1024);
      $_->{transferred_mb} = sprintf("%.01f",$_->{transferred}/1024/1024);
      # Prevent odd speeds from being displayed
      $_->{is_starting} = 1 if $_->{transferred} < 2**20 && $_->{status} eq 'MOVING';
   }
   my $srv_list = $db->SelectARef("SELECT s.srv_name,
                                   SUM(IF(q.status='PENDING',1,0)) as num_pending,
                                   SUM(IF((q.status='MOVING' AND q.updated>=NOW()-INTERVAL 60 SECOND),1,0)) as num_moving,
                                   SUM(IF((q.status='MOVING' AND q.updated<NOW()-INTERVAL 60 SECOND),1,0)) as num_stucked,
                                   SUM(IF(q.status='ERROR',1,0)) as num_error
                                   FROM QueueTransfer q, Servers s
                                   WHERE q.srv_id2=s.srv_id
                                   GROUP BY srv_id2
                                  ");
   $ses->PrintTemplate("admin_transfer_list.html",
                       list => $list, 
                       restartall=>@stucked>0?join(',',@stucked):0,
                       srv_list => $srv_list,
                       'token'      => $ses->genToken,
                      );
}

sub AdminUpdateServerStats
{
   
   return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
   return $ses->message("No servers selected") if !$f->{srv_id};
   my $ids = join ',', @{ARef($f->{srv_id})};
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_id IN ($ids)");
   for my $s (@$servers)
   {
      my $res = $ses->api($s->{srv_cgi_url},
                          {
                             fs_key => $s->{srv_key},
                             op     => 'get_file_stats',
                          }
                         );
      return $ses->message("Error when requesting API.<br>$res") unless $res=~/^OK/;
      my ($files,$size) = $res=~/^OK:(\d+):(\d+)$/;
      return $ses->message("Invalid files,size values: ($files)($size)") unless $files=~/^\d+$/ && $size=~/^\d+$/;
      my $file_count = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE srv_id=?",$s->{srv_id});
      $db->Exec("UPDATE Servers SET srv_files=?, srv_disk=? WHERE srv_id=?",$file_count,$size,$s->{srv_id});
   }
   return $ses->redirect('?op=admin_servers');
}

sub AdminServerImport
{
   
   if($f->{'import'} && $ses->checkToken)
   {
      my $usr_id = $db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{usr_login});
      return $ses->message("No such user '$f->{usr_login}'") unless $usr_id;
      my $res = $ses->api2($f->{srv_id},{op=>'import_list_do','usr_id'=>$usr_id,'pub'=>$f->{pub}});
      return $ses->message("Error happened: $res") unless $res=~/^OK/;
      $res=~/^OK:(\d+)/;
      return $ses->message("$1 files were completely imported to system");
   }
   my $res = $ses->api2($f->{srv_id},{op=>'import_list'});
   return $ses->message("Error when requesting API.<br>$res") unless $res=~/^OK/;
   my ($data) = $res=~/^OK:(.*)$/;
   my @files;
   for(split(/:/,$data))
   {
      /^(.+?)\-(\d+)$/;
      push @files, {name=>$1,size=>sprintf("%.02f Mb",$2/1048576)};
   }
   $ses->PrintTemplate("admin_server_import.html",
                       'files'   => \@files,
                       'srv_id'  => $f->{srv_id},
                       'token'      => $ses->genToken,
                      );
}

sub AdminServerDelete
{
   return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
   
   if($f->{password})
   {
      my $user = XUtils::CheckLoginPass($ses, $ses->getUser->{usr_login}, $f->{password});
      return $ses->message("Wrong password") if !$user;
   }
   else
   {
      $ses->PrintTemplate("confirm_password.html",
                          'msg'=>"Delete File Server and all files on it?",
                          'btn'=>"DELETE",
                          'op'=>'admin_server_del',
                          'id'=>$f->{srv_id});
   }

   my $srv = $db->SelectRow("SELECT * FROM Servers WHERE srv_id=?",$f->{id});
   return $ses->message("No such server") unless $srv;

   $db->Exec("DELETE FROM Files WHERE srv_id=?", $srv->{srv_id});
   $db->Exec("DELETE FROM Servers WHERE srv_id=?", $srv->{srv_id});

   return $ses->redirect('?op=admin_servers');
}

sub AdminSettings
{
   require PerlConfig;

   if($f->{last_notify_time})
   {
      $db->Exec("INSERT INTO Misc SET name='last_notify_time', value='$f->{last_notify_time}'
                     ON DUPLICATE KEY UPDATE value='$f->{last_notify_time}'");
      print "Content-type: text/html\n\nOK";
      return;
   }

   if($f->{expiry_csv})
   {
      print qq{Content-Disposition: attachment; filename="[$c->{site_name}] file deletion.csv"\n};
      print "Content-type: text/csv\n\n";
      open FILE, "$c->{cgi_path}/temp/expiry_confirmation.csv";
      print $_ while <FILE>;
      close FILE;
      return;
   }

   if($f->{expiry_confirm})
   {
      $db->Exec("DELETE FROM Misc WHERE name='mass_del_confirm_request'");
      $db->Exec("INSERT INTO Misc SET name='mass_del_confirm_response', value=UNIX_TIMESTAMP()
         ON DUPLICATE KEY UPDATE value=UNIX_TIMESTAMP()");
      $ses->redirect('/?op=admin_settings');
   }

   my @multiline = qw(ip_not_allowed external_links mailhosts_not_allowed coupons fnames_not_allowed bad_comment_words bad_ads_words m_a_code external_keys);
   push @multiline, grep { /_logins$/ } keys(%$c);

   $c->{$_} =~ s/\|/\n/g for @multiline;

   if($f->{save} && $ENV{REQUEST_METHOD} eq 'POST' && $ses->checkToken)
   {
      return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
      $db->Exec("DELETE FROM Misc WHERE name='mass_del_confirm_request'");
      my @fields = qw(license_key
                      site_name
                      enable_file_descr
                      enable_file_comments
                      ext_allowed
                      ext_not_allowed
                      ext_not_expire
                      ip_not_allowed
                      fnames_not_allowed
                      captcha_mode
                      email_from
                      contact_email
                      symlink_expire
                      items_per_page
                      lang_detection
                      ga_tracking_id
                      payment_plans
                      paypal_email
                      paypal_subscription
                      alertpay_email
                      item_name
                      currency_code
                      currency_symbol
                      link_format
                      enable_catalogue
                      pre_download_page
                      pre_download_page_alt
                      bw_limit_days
                      up_limit_days
                      reg_enabled
                      registration_confirm_email
                      mailhosts_not_allowed
                      sanitize_filename
                      bad_comment_words
                      add_filename_postfix
                      image_mod
                      mp3_mod
                      mp3_mod_no_download
                      mp3_mod_autoplay
                      mp3_mod_embed
                      recaptcha_pub_key
                      recaptcha_pri_key
                      solvemedia_theme
                      solvemedia_challenge_key
                      solvemedia_verification_key
                      solvemedia_authentication_key
                      iframe_breaker
                      file_public_default
                      agree_tos_default
                      mask_dl_link
                      files_approve
                      files_approve_regular_only
                      m_c
                      m_j
                      m_j_domain
                      m_j_instant
                      m_j_hide
                      m_z
                      m_o

                      facebook_app_id
                      facebook_app_secret
                      google_app_id
                      google_app_secret
                      vk_app_id
                      vk_app_secret
                      twit_consumer1
                      twit_consumer2
                      twit_enable_posting
                      coupons
                      tla_xml_key
                      m_i
                      m_i_adult
                      m_v
                      m_r
                      m_d
                      m_a
                      m_a_code
                      m_d_f
                      m_d_a
                      m_d_c
                      m_v_page
                      m_v_player
                      m_i_width
                      m_i_height
                      m_i_resize
                      m_i_wm_position
                      m_i_wm_image
                      m_i_wm_padding
                      m_i_hotlink_orig
                      ping_google_sitemaps
                      deurl_site
                      deurl_api_key
                      show_last_news_days
                      link_ip_logic
                      m_v_width
                      m_v_height
                      m_n
                      m_n_100_complete
                      m_n_100_complete_percent
                      ftp_mod
                      payout_systems
                      m_e
                      m_e_vid_width
                      m_e_vid_quality
                      m_e_audio_bitrate
                      m_e_flv
                      m_e_flv_bitrate
                      m_e_preserve_orig
                      m_e_copy_when_possible
                      m_b
                      m_k
                      m_k_plans
                      m_k_manual
                      m_g
                      show_direct_link
                      max_login_attempts_h
                      max_login_ips_h
                      mobile_design
                      docviewer
                      docviewer_no_download
                      memcached_location
                      payout_policy
                      dmca_expire
                      trash_expire
                      external_keys
                      enable_reports
                      adfly_uid
                      captcha_attempts_h
                      traffic_plans
                      ftp_upload_reg
                      ftp_upload_prem
                      no_adblock_earnings

                      enabled_anon
                      max_upload_files_anon
                      max_upload_filesize_anon
                      max_downloads_number_anon
                      download_countdown_anon
                      captcha_anon
                      ads_anon
                      add_download_delay_anon
                      bw_limit_anon
                      up_limit_anon
                      remote_url_anon
                      leech_anon
                      direct_links_anon
                      down_speed_anon
                      max_download_filesize_anon
                      torrent_fallback_after_anon
                      video_embed_anon
                      flash_upload_anon
                      files_expire_access_anon
                      file_dl_delay_anon
                      mp3_embed_anon
                      rar_info_anon
                      m_n_upload_speed_anon
                      m_n_limit_conn_anon
                      m_n_dl_resume_anon

                      enabled_reg
                      max_upload_files_reg
                      disk_space_reg
                      max_upload_filesize_reg
                      max_downloads_number_reg
                      download_countdown_reg
                      captcha_reg
                      ads_reg
                      add_download_delay_reg
                      bw_limit_reg
                      up_limit_reg
                      remote_url_reg
                      leech_reg
                      direct_links_reg
                      down_speed_reg
                      max_download_filesize_reg
                      max_rs_leech_reg
                      torrent_dl_reg
                      torrent_dl_slots_reg
                      torrent_fallback_after_reg
                      video_embed_reg
                      flash_upload_reg
                      files_expire_access_reg
                      file_dl_delay_reg
                      mp3_embed_reg
                      rar_info_reg
                      m_n_upload_speed_reg
                      m_n_limit_conn_reg
                      m_n_dl_resume_reg

                      enabled_prem
                      max_upload_files_prem
                      disk_space_prem
                      max_upload_filesize_prem
                      max_downloads_number_prem
                      download_countdown_prem
                      captcha_prem
                      ads_prem
                      add_download_delay_prem
                      bw_limit_prem
                      up_limit_prem
                      remote_url_prem
                      leech_prem
                      direct_links_prem
                      down_speed_prem
                      max_download_filesize_prem
                      max_rs_leech_prem
                      torrent_dl_prem
                      torrent_dl_slots_prem
                      torrent_fallback_after_prem
                      video_embed_prem
                      flash_upload_prem
                      files_expire_access_prem
                      file_dl_delay_prem
                      mp3_embed_prem
                      rar_info_prem
                      m_n_upload_speed_prem
                      m_n_limit_conn_prem
                      m_n_dl_resume_prem

                      tier_sizes
                      tier1_countries
                      tier2_countries
                      tier3_countries
                      tier1_money
                      tier2_money
                      tier3_money
                      tier4_money
                      image_mod_no_download
                      video_mod_no_download
                      external_links
                      show_server_stats
                      show_splash_main
                      clean_ip2files_days
                      anti_dupe_system
                      two_checkout_sid
                      plimus_contract_id
                      moneybookers_email
                      max_money_last24
                      sale_aff_percent
                      referral_aff_percent
                      min_payout
                      del_money_file_del
                      convert_money
                      convert_days
                      money_filesize_limit
                      dl_money_anon
                      dl_money_reg
                      dl_money_prem
                      show_more_files
                      bad_ads_words
                      cron_test_servers
                      m_i_magick
                      deleted_files_reports
                      image_mod_track_download
                      m_x
                      m_x_rate
                      m_x_prem
                      m_y
                      m_y_ppd_dl
                      m_y_ppd_sales
                      m_y_ppd_rebills
                      m_y_pps_dl
                      m_y_pps_sales
                      m_y_pps_rebills
                      m_y_mix_dl
                      m_y_mix_sales
                      m_y_mix_rebills
                      m_y_default
                      m_y_interval_days
                      m_y_manual_approve
                      m_y_embed_earnings
                      no_money_from_uploader_ip
                      no_money_from_uploader_user
                      m_p_premium_only
                      admin_geoip
                      upload_on_anon
                      upload_on_reg
                      upload_on_prem
                      download_on_anon
                      download_on_reg
                      download_on_prem
                      paypal_trial_days
                      happy_hours
                      no_anon_payments
                      maintenance_upload 
                      maintenance_upload_msg
                      maintenance_download
                      maintenance_download_msg
                      maintenance_full
                      maintenance_full_msg
                      upload_disabled_countries
                      download_disabled_countries
                      torrent_autorestart
                      comments_registered_only
                      catalogue_registered_only
                     );

       my $ftp_status_changed = 1 if $f->{ftp_mod} != $c->{ftp_mod};
       if($f->{ftp_mod} && $ftp_status_changed && !$f->{ftp_upload_reg} && !$f->{ftp_upload_prem})
       {
           $f->{ftp_upload_reg} = $f->{ftp_upload_prem} = 1;
       }

       push @fields, map { $_->{name} } @{ &getPluginsOptions('Payments') };
       push @fields, map { $_->{name} } @{ &getPluginsOptions('Leech') };
       push @fields, map { $_->{name} } @{ &getPluginsOptions('Video') };

       my @fields_fs = qw(site_url 
                         site_cgi 
                         ext_allowed 
                         ext_not_allowed 
                         ip_not_allowed
                         dl_key
                         m_i
                         m_v
                         m_r
                         m_i_width
                         m_i_height
                         m_i_resize
                         m_i_wm_position
                         m_i_wm_image
                         m_i_wm_padding
                         m_i_hotlink_orig
                         m_e
                         m_e_vid_width
                         m_e_vid_quality
                         m_e_audio_bitrate
                         m_e_flv
                         m_e_flv_bitrate
                         m_e_preserve_orig
                         m_e_copy_when_possible
                         m_b
                         m_i_magick
                         external_keys

                         enabled_anon
                         max_upload_files_anon
                         max_upload_filesize_anon
                         remote_url_anon
                         max_rs_leech_anon
                         leech_anon

                         enabled_reg
                         max_upload_files_reg
                         max_upload_filesize_reg
                         remote_url_reg
                         max_rs_leech_reg
                         leech_reg

                         enabled_prem
                         max_upload_files_prem
                         max_upload_filesize_prem
                         remote_url_prem
                         max_rs_leech_prem
                         leech_prem
                        );

      push @fields_fs, map { $_->{name} } @{ &getPluginsOptions('Leech') };

      $f->{payment_plans}=~s/\s//gs;
      $f->{item_name} = uri_escape($f->{item_name});

      for(qw(ip_not_allowed fnames_not_allowed mailhosts_not_allowed bad_comment_words bad_ads_words))
      {
         $f->{$_} = "($f->{$_})" if $f->{$_};
      }

      eval { PerlConfig::Write("$c->{cgi_path}/XFileConfig.pm", $f, fields => \@fields, multiline => \@multiline) };
      return $ses->message($@) if $@;

      $f->{site_url}=$c->{site_url};
      $f->{site_cgi}=$c->{site_cgi};
      $f->{dl_key}  =$c->{dl_key};

      my $data = join('~',map{"$_:$f->{$_}"}@fields_fs);
      
      my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF' AND srv_cdn=''");
      $|++;
      print"Content-type:text/html\n\n<HTML><BODY style='font:13px Arial;background:#eee;text-align:center;'>Have ".($#$servers+1)." servers to update.<br><br>";
      my $failed=0;
      for(@$servers)
      {
         print"ID=$_->{srv_id} $_->{srv_name}...";
         my $res = $ses->api($_->{srv_cgi_url},{ fs_key=>$_->{srv_key}, op=>'update_conf', data=>$data });
         if($res eq 'OK')
         {
            print"OK<br>";
         }
         else
         {
            print"FAILED: $res<br>";
            $failed++;
         }
         #return $ses->message("Can\'t update config for server ID: $_->{srv_id}:$res") unless $res eq 'OK';
      }
      print"<br><br>Done.<br>$failed servers failed to update.<br><br><a href='?op=admin_settings'>Back to Site Settings</a>";
      print"<Script>window.location='$c->{site_url}/?op=admin_settings';</Script>" unless $failed;
      print"</BODY></HTML>";
      return;
      #print return $ses->redirect('?op=admin_settings');
   }

   $c->{ip_not_allowed}=~s/[\^\(\)\$\\]//g;
   $c->{ip_not_allowed}=~s/d\+/*/g;
   $c->{fnames_not_allowed}=~s/[\^\(\)\$\\]//g;
   $c->{mailhosts_not_allowed}=~s/[\^\(\)\$\\]//g;
   $c->{bad_comment_words}=~s/[\^\(\)\$\\]//g;
   $c->{bad_ads_words}=~s/[\^\(\)\$\\]//g;
   $c->{"link_format$c->{link_format}"}=' selected';
   $c->{"enp_$_"}=$ses->iPlg($_) for split('',$ses->{plug_lett});
   #die $c->{"enp_h"};
   $c->{tier_sizes}||='0|10|100';
   $c->{tier1_countries}||='US|CA';
   $c->{tier1_money}||='1|2|3';
   $c->{tier2_countries}||='DE|FR|GB';
   $c->{tier2_money}||='1|2|3';
   $c->{tier3_money}||='1|2|3';
   $c->{"lil_$c->{link_ip_logic}"}=' checked';
   $c->{external_links}=~s/~/\n/gs;
   $c->{"m_i_wm_position_$c->{m_i_wm_position}"}=1;
   $c->{m_m} = $ses->iPlg('m');
   $c->{cliid} = $ses->{cliid};
   $c->{"m_v_page_".$c->{m_v_page}}=1;
   $c->{"m_y_default_$c->{m_y_default}"}=1;
   $c->{"lang_detection_$c->{lang_detection}"}=1;

   for(@multiline)
   {
      $c->{$_} =~ s/\|/\n/g;
   }

   if($c->{tla_xml_key})
   {
      my $chmod = (stat("$c->{cgi_path}/Templates/text-link-ads.html"))[2] & 07777;
      my $chmod_txt = sprintf("%04o", $chmod);
      $c->{tla_msg}="Set chmod 666 to this file: Templates/text-link-ads.html" unless $chmod_txt eq '0666';
   }

   $c->{geoip_ok}=1 if -f "$c->{cgi_path}/GeoIP.dat";

   my @messages;
   my $t0 = $db->SelectOne("SELECT value FROM Misc WHERE name='last_cron_time'") || 0;
   my $dt = sprintf("%.0f", (time-$t0)/3600 );
   $dt=999 unless $t0;
   push @messages, {info=>"cron.pl have not been running for $dt hours. Set up cronjob or <a href='$c->{site_cgi}/cron.pl'>run it manually</a>."} if $dt>3;

   my @vidplgs = grep { $_->{listed} } $ses->getPlugins('Video')->options();
   my ($vidplg) = grep { $_->{name} eq $c->{m_v_player} } @vidplgs;
   my @s_fields = @{ $vidplg->{s_fields} } if $vidplg;
   map { $_->{value} = $c->{$_->{name}} } @s_fields;
   $vidplg->{selected} = 1 if $vidplg;

   my @leeches_list = map { eval "\$$_\::options" } $ses->getPlugins('Leech');
   for(@leeches_list)
   {
      $_->{name} = "$_->{plugin_prefix}_logins";
      $_->{value} = $c->{$_->{name}};
      $_->{domain} = ucfirst($_->{domain});
   }

   my $last_notify_time = $db->SelectOne("SELECT value FROM Misc WHERE name='last_notify_time'");
   my $mass_del_confirm_request = $db->SelectOne("SELECT value FROM Misc WHERE name='mass_del_confirm_request'");
   my $fastcgi = 1 if $ENV{FCGI_ROLE};

   $ses->PrintTemplate("admin_settings.html",
                       %{$c},
                       "captcha_$c->{captcha_mode}" => ' checked',
                       "payout_policy_$c->{payout_policy}" => ' checked',
                       "solvemedia_theme_$c->{solvemedia_theme}" => ' selected',
                       'item_name'     => uri_unescape($c->{item_name}),
                       'messages'      => \@messages,
                       'payments_list' => &getPluginsOptions('Payments'),
                       'leeches_list' => &getPluginsOptions('Leech'),
                       'token'      => $ses->genToken,
                       'version'    => $ses->getVersion,
                       'last_notify_time' => $last_notify_time||0,
                       'vidplgs'    => \@vidplgs,
                       'mass_del_confirm_request' => $mass_del_confirm_request,
                       'fastcgi' => $fastcgi,
                      );
}

sub getPluginsOptions
{
   my ($plgsection, $data) = @_;
   my @ret;
   for($ses->getPlugins($_[0]))
   {
      my $hashref = eval("\$$_\::options") || $_->options;
      my $aref = [];

      # Regular plugins
      $aref = $hashref->{s_fields} if $hashref->{s_fields};

      # Compatibility with XFM Leech plugins
      $aref = [ { name => "$hashref->{plugin_prefix}\_logins", domain => ucfirst($hashref->{domain}) } ] if $hashref->{plugin_prefix};

      $_->{value} = $data ? $data->{$_->{name}} : $c->{$_->{name}} for @$aref;
      $_->{"type_$_->{type}"} = 1 for @$aref;

      push @ret, @$aref;
   }
   return \@ret;
}

sub formatAmount
{
   my $arg = shift;
   $arg=~s/(\.[^0]*)0+$/$1/;
   $arg=~s/\.$//;
   return $arg;
}

sub MyReports
{
   return $ses->message("Not allowed") unless $c->{enable_reports};

   if($f->{section} eq 'downloads')
   {
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      my $list = $db->SelectARef("SELECT f.*, 
                  INET_NTOA(ip) AS ip2,
                  i.usr_id AS downloader_id,
                  i.referer AS referer,
                  i.money AS money,
                  i.status AS status,
                  u.usr_premium_expire > NOW() AS premium_download
                  FROM IP2Files i
                  LEFT JOIN Files f ON f.file_id = i.file_id
                  LEFT JOIN Users u ON u.usr_id = i.usr_id
                  WHERE i.owner_id=?
                  AND DATE(created)=?",
                  $ses->getUserId,
                  $f->{day},
                  );
      for(@$list)
      {
         $_->{download_link} = $ses->makeFileLink($_);
         $_->{country} = $gi->country_code_by_addr($_->{ip2});
         $_->{usr_login} = $db->SelectOne("SELECT usr_login FROM Users WHERE usr_id=?", $_->{downloader_id}) || ' - ';
         $_->{referer} = $ses->SecureStr($_->{referer});
         my $ref_url = "http://$_->{referer}" if $_->{referer} !~ /^\//;
         $_->{domain} = $ses->getDomain($ref_url);
      }
      return $ses->PrintTemplate("my_reports_downloads.html",
                           list => $list);
   }
   if($f->{section} =~ /^(sales|rebills|sites)$/)
   {
      my @domains = map { $_->{domain} } @{ $db->SelectARef("SELECT DISTINCT(domain) FROM Websites WHERE usr_id=?", $ses->getUserId) };
      map { $_ =~ s/[\\']//g; } @domains;
      my $domains = join("','", @domains);
      my $usr_id = $ses->getUserId||0;
      my $filter = {
         'sales' => "aff_id=$usr_id AND rebill=0",
         'rebills' => "aff_id=$usr_id AND rebill=1",
         'sites' => "domain != '' AND domain IN ('$domains')",
      }->{$f->{section}};
      return $ses->message("No section") if !$filter;
      my $list = $db->SelectARef("SELECT *, INET_NTOA(ip) AS ip2 FROM Transactions
                     WHERE DATE(created)=?
                     AND $filter
                     AND verified",
                     $f->{day},
                     );
      require Geo::IP;
      my $gi = Geo::IP->new("$c->{cgi_path}/GeoIP.dat");
      for(@$list) {
         my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?", $_->{file_id});
         $_->{file_name} = $file->{file_name};
         $_->{download_link} = $ses->makeFileLink($file);
         $_->{country} = $gi->country_code_by_addr($_->{ip2});
      }
      return $ses->PrintTemplate("my_reports_sales.html",
            %{$f},
            list => $list);
   }
   if($f->{section} eq 'refs')
   {
      my $list = $db->SelectARef("SELECT * FROM PaymentsLog
                  WHERE usr_id_to=?
                  AND DATE(created)=?
                  AND type=?",
                  $ses->getUserId,
                  $f->{day},
                  $f->{section});
      for(@$list) {
         $_->{usr_login_from} = $db->SelectOne("SELECT usr_login FROM Users WHERE usr_id=?", $_->{usr_id_from});
      }
      return $ses->PrintTemplate("my_reports_refs.html",
            list => $list);
   }

   my @d1 = $ses->getTime();
   $d1[2]='01';
   my @d2 = $ses->getTime();
   my $day1 = $f->{date1}=~/^\d\d\d\d-\d\d-\d\d$/ ? $f->{date1} : "$d1[0]-$d1[1]-$d1[2]";
   my $day2 = $f->{date2}=~/^\d\d\d\d-\d\d-\d\d$/ ? $f->{date2} : "$d2[0]-$d2[1]-$d2[2]";
   my $list = $db->SelectARef("SELECT *, DATE_FORMAT(day,'%b, %e') as day2, UNIX_TIMESTAMP(day) AS timestamp
                               FROM Stats2
                               WHERE usr_id=?
                               AND day>=?
                               AND day<=?
                               ORDER BY day",$ses->getUserId,$day1,$day2);

   # Generating table
   my %totals;
   my (@days,@profit_dl,@profit_sales,@profit_refs);
   my $oldest_ip2files_timestamp = $db->SelectOne("SELECT UNIX_TIMESTAMP(MIN(created)) FROM IP2Files");
   for my $x (@$list)
   {
      $x->{profit_total} += $x->{$_} for qw(profit_dl profit_sales profit_rebills profit_refs profit_site);
      $totals{"sum_$_"}+=$x->{$_} for keys(%$x);
      for(keys(%$x)) {
         $x->{$_}=&formatAmount($x->{$_}) if $_ =~ /^profit_/;
      }
      $x->{has_dl_details} = $x->{timestamp} > $oldest_ip2files_timestamp;
   }
   foreach(keys %totals) {
      $totals{$_} = &formatAmount($totals{$_}) if $_ =~ /^sum_profit_/;
   }

   return $ses->PrintTemplate("my_reports.html",
                       list => $list,
                       data => JSON::encode_json($list),
                       date1 => $day1,
                       date2 => $day2,
                       %totals,
                       m_x   => $c->{m_x},
                       currency_code => $c->{currency_code},
                       currency_symbol => ($c->{currency_symbol}||'$'),
                      );
}

sub genChart
{
   use List::Util qw(max);
   my ($list, $field, %opts) = @_;

   my @ret;
   push @ret, [ 'Date', $field ];
   push @ret, map { [ $_->{x}, int($_->{$field}) ] } @$list;

   return \@ret;
};

sub AdminStats
{
   my @d1 = $ses->getTime(time-10*24*3600);
   my @d2 = $ses->getTime();
   my $day1 = $f->{date1}=~/^\d\d\d\d-\d\d-\d\d$/ ? $f->{date1} : "$d1[0]-$d1[1]-$d1[2]";
   my $day2 = $f->{date2}=~/^\d\d\d\d-\d\d-\d\d$/ ? $f->{date2} : "$d2[0]-$d2[1]-$d2[2]";
   $f->{section} ||= 'charts';
   my %tmpl_opts = (
                       date1 => $day1,
                       date2 => $day2,
                       m_x => $c->{m_x},
                       section => $f->{section},
                       "section_$f->{section}" => 1,
                    );

   my $list = $db->SelectARef("SELECT *, ROUND(bandwidth/1048576) as bandwidth, DATE_FORMAT(day,'%b%e') as x
                               FROM Stats
                               WHERE day>=?
                               AND day<=?",$day1,$day2);

   my $data = [
      { title => 'File uploads', color => 'blue', data => genChart($list, 'uploads') },
      { title => 'File downloads', color => 'black', data => genChart($list, 'downloads') },
      { title => 'New users', color => 'orange', data => genChart($list, 'registered') },
      { title => 'Bandwidth', color => 'red', units => 'Mb', data => genChart($list, 'bandwidth') },
      { title => 'Payments received', color => 'green', units => $c->{currency_code}, data => genChart($list, 'received') },
      { title => 'Paid to users', color => 'brown', units => $c->{currency_code}, data => genChart($list, 'paid_to_users') },
   ];

   if(!$f->{section} || $f->{section} eq 'charts')
   {
      return $ses->PrintTemplate('admin_stats.html',
                             %tmpl_opts,
                             data => JSON::encode_json($data),
                      );
   }

   if($f->{section} eq 'details')
   {
      my %totals;
      for my $x(@$list)
      {
         $x->{received} = sprintf("%0.2f", $x->{received});
         $x->{paid_to_users} = sprintf("%0.2f", $x->{paid_to_users});
	      $x->{income} = $x->{received} - $x->{paid_to_users};
	      $totals{"sum_$_"}+=$x->{$_} for keys(%$x);
      }
      return $ses->PrintTemplate('admin_stats.html',
                             %tmpl_opts,
                             %totals,
                             list  => $list,
                      );
   }

   if($f->{section} eq 'sites') {
      my $list_sites = $db->SelectARef("SELECT *,
                                        DATE(created) AS day,
                                        COUNT(id) AS sales,
                                        SUM(amount) AS profit_sales
               FROM Transactions
               WHERE verified
               AND domain!=''
               AND DATE(created) >= ?
               AND DATE(created) <= ?
               GROUP BY DATE(created), domain",
               $day1,
               $day2);
      foreach(@$list_sites) {
         my $site = $db->SelectRow("SELECT * FROM Websites WHERE domain=?", $_->{domain});
         my $owner = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $site->{usr_id}) if $site;
         $_->{usr_login} = $owner->{usr_login} if $owner;
         $_->{profit_sales} = sprintf("%0.2f", $_->{profit_sales}||0);
      }
      return $ses->PrintTemplate('admin_stats.html',
                             %tmpl_opts,
                             list_sites  => $list_sites,
                             'currency_symbol' => ($c->{currency_symbol}||'$'),
                      );
   }

   if($f->{section} eq 'payments') {
      my $list_transactions = $db->SelectARef("SELECT *,
                  DATE(created) AS day,
               COUNT(id) AS sales,
               SUM(amount) AS profit_sales
               FROM Transactions
               WHERE verified
               AND plugin != ''
               AND DATE(created) >= ?
               AND DATE(created) <= ?
               GROUP BY DATE(created), plugin",
               $day1,
               $day2);
      return $ses->PrintTemplate('admin_stats.html',
                             %tmpl_opts,
                             list  => $list_transactions,
                      );
   }
}

sub AdminComments
{
   return $ses->message("Access denied") if !$ses->getUser->{usr_adm} && !($c->{m_d} && $ses->getUser->{usr_mod} && $c->{m_d_c});
   if($ses->checkToken() && $f->{del_selected} && $f->{cmt_id})
   {
      my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{cmt_id})});
      return $ses->redirect($c->{site_url}) unless $ids;
      $db->Exec("DELETE FROM Comments WHERE cmt_id IN ($ids)");
      return $ses->redirect("?op=admin_comments");
   }
   if($f->{rr})
   {
      return $ses->redirect( &CommentRedirect(split(/-/,$f->{rr})) );
   }
   my $filter;
   $filter="WHERE c.cmt_ip=INET_ATON('$f->{ip}')" if $f->{ip};
   $filter="WHERE c.usr_id=$f->{usr_id}" if $f->{usr_id};
   $filter="WHERE c.cmt_name LIKE '%$f->{key}%' OR c.cmt_email LIKE '%$f->{key}%' OR c.cmt_text LIKE '%$f->{key}%'" if $f->{key};
   my $list = $db->SelectARef("SELECT c.*, INET_NTOA(c.cmt_ip) as ip, u.usr_login, u.usr_id,
                                 f.file_name, f.file_code,
                                 n.news_id, n.news_title
                               FROM Comments c
                               LEFT JOIN Users u ON c.usr_id=u.usr_id
                               LEFT JOIN Files f ON f.file_id=c.cmt_ext_id
                               LEFT JOIN News n ON n.news_id=c.cmt_ext_id
                               $filter
                               ORDER BY created DESC".$ses->makePagingSQLSuffix($f->{page},$f->{per_page}));
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Comments c $filter");

   for(@$list)
   {
      $_->{"cmt_type_$_->{cmt_type}"} = 1;
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{news_link} = "$c->{site_url}/n$_->{news_id}-" . lc($_->{news_title}) . ".html";
   }

   $ses->PrintTemplate("admin_comments.html",
                       'list'   => $list,
                       'key'    => $f->{key}, 
                       'paging' => $ses->makePagingLinks($f,$total),
                       'token' => $ses->genToken,
                      );
}

sub AdminCommentEdit
{
   if($ses->checkToken() && $f->{save})
   {
      $db->Exec("UPDATE Comments SET cmt_text=? WHERE cmt_id=?", $f->{cmt_text}, $f->{cmt_id});
      return $ses->redirect("$c->{site_url}/?op=admin_comments");
   }
   my $comment = $db->SelectRow("SELECT *, u.usr_login, INET_NTOA(cmt_ip) AS ip,
         f.file_name, f.file_code,
         n.news_title,
         c.created
      FROM Comments c
      LEFT JOIN Users u ON u.usr_id=c.usr_id
      LEFT JOIN Files f ON f.file_id=c.cmt_ext_id
      LEFT JOIN News n ON n.news_id=c.cmt_ext_id
      WHERE cmt_id=?", $f->{cmt_id});
   return $ses->PrintTemplate("admin_comment_form.html",
      %{ $comment },
      download_link => $ses->makeFileLink($comment),
      "cmt_type_$comment->{cmt_type}" => 1,
      token => $ses->genToken);
}

sub AdminPayments
{
   
   if($f->{export_file} && $f->{pay_id} && $ses->checkToken)
   {
      my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{pay_id})});
      return $ses->redirect($c->{site_url}) unless $ids;
      my $list = $db->SelectARef("SELECT p.*, u.usr_id, u.usr_pay_email, u.usr_pay_type
                                  FROM Payments p, Users u
                                  WHERE id IN ($ids)
                                  AND status='PENDING'
                                  AND p.usr_id=u.usr_id");
      my $date = sprintf("%d-%d-%d",&getTime());
      print qq{Content-Type: application/octet-stream\n};
      print qq{Content-Disposition: attachment; filename="paypal-mass-pay-$date.txt"\n};
      print qq{Content-Transfer-Encoding: binary\n\n};
      for my $x (@$list)
      {
         next unless $x->{usr_pay_type} =~ /paypal/i;
         print"$x->{usr_pay_email}\t$x->{amount}\t$c->{currency_code}\tmasspay_$x->{usr_id}\tPayment\r\n";
      }
      return;
   }
   if($f->{mark_paid} && $f->{pay_id} && $ses->checkToken)
   {
      my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{pay_id})});
      return $ses->redirect($c->{site_url}) unless $ids;
      $db->Exec("UPDATE Payments SET status='PAID' WHERE id IN ($ids)" );
      return $ses->redirect_msg("$c->{site_url}/?op=admin_payments","Selected payments marked as Paid");
   }
   if($f->{mark_rejected} && $f->{pay_id} && $ses->checkToken)
   {
      my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{pay_id})});
      return $ses->redirect($c->{site_url}) unless $ids;
      $db->Exec("UPDATE Payments SET status='REJECTED', info=? WHERE id IN ($ids)",
                  $f->{reject_info}||'');
      return $ses->redirect_msg("$c->{site_url}/?op=admin_payments","Selected payments marked as Rejected");
   }
   if($f->{history})
   {
	   my $list = $db->SelectARef("SELECT p.*, u.usr_login, u.usr_email
         FROM Payments p
         LEFT JOIN Users u ON u.usr_id=p.usr_id
         ORDER BY created");

      my $total = $db->SelectOne("SELECT COUNT(*) FROM Payments");

      $ses->PrintTemplate('admin_payments_history.html',
         'list' => $list,
         'paging' => $ses->makePagingLinks($f,$total));
   }

   my $list = $db->SelectARef("SELECT p.*, u.usr_login, u.usr_email, u.usr_pay_email, u.usr_pay_type
                               FROM Payments p, Users u
                               WHERE status='PENDING'
                               AND p.usr_id=u.usr_id
                               ORDER BY created");
   for(@$list)
   {
      $_->{class} = 'payment_green' if $db->SelectOne("SELECT COUNT(*)
                               FROM Payments
                               WHERE usr_id=?
                               AND status='PAID'",
                               $_->{usr_id}) >= 2;
   }
   my $amount_sum = $db->SelectOne("SELECT SUM(amount) FROM Payments WHERE status='PENDING'");
   $ses->PrintTemplate("admin_payments.html",
                       'list' => $list,
                       'amount_sum' => $amount_sum,
                       'paypal_email'        => $c->{paypal_email},
                       'alertpay_email'      => $c->{alertpay_email},
                       'webmoney_merchant_id'=> $c->{webmoney_merchant_id},
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                       'token'      => $ses->genToken,
                       );
}

sub MyAccount
{
   my $m_y_change_ok;
   if($ses->iPlg('p') && $c->{m_y_interval_days})
   {
      $m_y_change_ok=1 unless  $db->SelectOne("SELECT usr_id FROM Users WHERE usr_id=? AND usr_profit_mode_changed>NOW()-INTERVAL ? DAY",$ses->getUserId,$c->{m_y_interval_days});
   }
   if($f->{twitter1})
   {
      require Net::Twitter::Lite::WithAPIv1_1;
      my $nt = Net::Twitter::Lite::WithAPIv1_1->new(consumer_key    => $c->{twit_consumer1},
                                       consumer_secret => $c->{twit_consumer2} );
      my $url = $nt->get_authorization_url(callback => "$c->{site_url}/?op=my_account&twitter2=1");
      $ses->setCookie('tw_token',$nt->request_token);
      $ses->setCookie('tw_token_secret',$nt->request_token_secret);
      return $ses->redirect($url);
   }
   if($f->{twitter2})
   {
      require Net::Twitter::Lite::WithAPIv1_1;
      my $nt = Net::Twitter::Lite::WithAPIv1_1->new(consumer_key    => $c->{twit_consumer1},
                                       consumer_secret => $c->{twit_consumer2});

      $nt->request_token( $ses->getCookie('tw_token') );
      $nt->request_token_secret( $ses->getCookie('tw_token') );
      my($access_token, $access_token_secret, $user_id, $screen_name) = $nt->request_access_token(verifier => $f->{oauth_verifier});

      if($access_token && $access_token_secret)
      {
         $db->Exec("INSERT INTO UserData SET usr_id=?, name=?, value=? 
                    ON DUPLICATE KEY UPDATE value=?",$ses->getUserId, 'twitter_login', $access_token, $access_token);
         $db->Exec("INSERT INTO UserData SET usr_id=?, name=?, value=? 
                    ON DUPLICATE KEY UPDATE value=?",$ses->getUserId, 'twitter_password', $access_token_secret, $access_token_secret);
      }
   }
   if($f->{twitter_stop})
   {
      $db->Exec("DELETE FROM UserData WHERE usr_id=? AND name IN ('twitter_login','twitter_password')",$ses->getUserId);
      return $ses->redirect('?op=my_account');
   }
   if($f->{site_add} && $f->{site_validate})
   {
      $f->{site_add}=~s/^https?:\/\///i;
      $f->{site_add}=~s/^www\.//i;
      $f->{site_add}=~s/[\/\s]+//g;

      if(my $usr_id1 = $db->SelectOne("SELECT usr_id FROM Websites WHERE domain=?",$f->{site_add}))
      {
         return $ses->message("$f->{site_add} domain is already added by usr_id=$usr_id1");
      }

      my $site_key = lc $c->{site_url};
      $site_key=~s/^.+\/\///;
      $site_key=~s/\W//g;

      require LWP::UserAgent;
      my $ua = LWP::UserAgent->new(timeout => 10, agent   => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; ru; rv:1.9.1.6) Gecko/20091201 Firefox/3.5.6 (.NET CLR 3.5.30729)');
      my $res = $ua->get("http://$f->{site_add}/$site_key.txt")->content;
      $res=~s/[\r\n]+//g;
      my $ok;
      if($res=~/^\d+$/)
      {
         $ok=1 if $res == $ses->getUserId;
      }
      else
      {
         my $res = $ua->get("http://$f->{site_add}")->content;
         my $usr_id = $ses->getUserId;
         $ok=1 if $res=~/<meta\s+content="$usr_id"\s+name="$site_key"\s*\/?>/is;
         $ok=1 if $res=~/<meta\s+name="$site_key"\s+content="$usr_id"\s*\/?>/is;
      }
      if($ok)
      {
         $db->Exec("INSERT INTO Websites SET usr_id=?, domain=?, created=NOW()",$ses->getUserId,$f->{site_add});
         return $ses->redirect_msg("?op=my_account","$f->{site_add} domain was added to your account");
      }
      return $ses->redirect_msg("?op=my_account","Failed to verify $f->{site_add} domain");
   }
   if($f->{site_del})
   {
      $db->Exec("DELETE FROM Websites WHERE usr_id=? AND domain=? LIMIT 1",$ses->getUserId,$f->{site_del});
      return $ses->redirect_msg("?op=my_account","$f->{site_del} domain was successfully deleted");
   }
   if($f->{premium_key} && $c->{m_k})
   {
      my ($key_id,$key_code) = $f->{premium_key}=~/^(\d+)(\w+)$/;
      my $key = $db->SelectRow("SELECT * FROM PremiumKeys WHERE key_id=? AND key_code=?",$key_id,$key_code);
      return $ses->redirect_msg("?op=my_account","Invalid Premium Key") unless $key;
      return $ses->redirect_msg("?op=my_account","This Premium Key already used") if $key->{usr_id_activated};
      my ($val,$m) = $key->{key_time}=~/^(\d+)(\D*)$/;
      my $multiplier = { h => 1.0 / 24, d => 1, m => 3 }->{$m} || die("Unknown unit: $m");
      my $days = $val * $multiplier;
      $db->Exec("UPDATE PremiumKeys SET key_activated=NOW(), usr_id_activated=? WHERE key_id=?",$ses->getUserId,$key->{key_id});

      require IPN;
      my $ipn = IPN->new($ses);
      my $transaction = $ipn->createTransaction(amount => $key->{key_price},
                            days => $days,
                            usr_id => $ses->getUserId||0,
                            referer => $ses->getCookie('ref_url') || $ENV{HTTP_REFERER} || '',
                            aff_id => &getAffiliate()||0);
      $ipn->upgradePremium($transaction, days => $days);

      $m=~s/h/ hours/i;
      $m=~s/d/ days/i;
      $m=~s/m/ months/i;
      return $ses->redirect_msg("?op=my_account","$ses->{lang}->{lang_prem_key_ok}<br>$ses->{lang}->{lang_added_prem_time}: $val $m");
   }
   if ( $f->{matomy_status} ) {
      require IPN;
      print "Content-type: application/json\n\n";
      my $ipn = IPN->new($ses);
      my $transaction = $ipn->getLatestTransaction(usr_id => $ses->getUserId);
      die("No transaction") if !$transaction;
      print JSON::encode_json({ amount => $transaction->{amount},
                 usr_matomy_coins => int($ses->getUser->{usr_matomy_coins}),
                 active => $transaction->{id} eq $f->{matomy_status},
                 verified => int($transaction->{verified}) });
      return;
   }
   if($f->{enable_lock})
   {
      return $ses->message("Security Lock already enabled") if $ses->getUser->{usr_security_lock};
      my $rand = $ses->randchar(8);
      $db->Exec("UPDATE Users SET usr_security_lock=? WHERE usr_id=?",$rand,$ses->getUserId);
      return $ses->redirect_msg("?op=my_account",$ses->{lang}->{lang_lock_activated});
   }
   if($f->{disable_lock})
   {
      return $ses->message("Demo mode") if $c->{demo_mode} && $ses->getUser->{usr_login} eq 'admin';
      my $rand = $ses->getUser->{usr_security_lock};
      return $ses->message("Security Lock is not enabled") unless $rand;
      if($f->{code})
      {
         return $ses->message("Error: security code doesn't match") unless $f->{code} eq $rand;
         $db->Exec("UPDATE Users SET usr_security_lock='' WHERE usr_id=?",$ses->getUserId);
         return $ses->redirect_msg("?op=my_account",$ses->{lang}->{lang_lock_disabled});
      }
      $c->{email_text}=1;
      $ses->SendMail( $ses->getUser->{usr_email}, $c->{email_from}, "$c->{site_name}: disable security lock", "To disable Security Lock for your account follow this link:\n$c->{site_url}/?op=my_account&disable_lock=1&code=$rand" );
      return $ses->redirect_msg("?op=my_account",$ses->{lang}->{lang_lock_link_sent});
   }
   if($f->{settings_save} && $ENV{REQUEST_METHOD} eq 'POST' && $ses->checkToken)
   {
      return $ses->redirect($c->{site_url}) if !&CheckReferer($ENV{HTTP_REFERER});
      return $ses->message("Not allowed in Demo mode!") if $c->{demo_mode} && $ses->getUser->{usr_adm};
      my $user=$db->SelectRow("SELECT usr_login as usr_password,usr_email FROM Users WHERE usr_id=?",$ses->getUserId);
      if($f->{usr_login} && $user->{usr_login}=~/^\d+$/ && $f->{usr_login} ne $user->{usr_login})
      {
         $f->{usr_login}=$ses->SecureStr($f->{usr_login});
         return $ses->message("Error: Login should contain letters") if $f->{usr_login}=~/^\d+$/;
         return $ses->message("Error: $ses->{lang}->{lang_login_too_short}") if length($f->{usr_login})<4;
         return $ses->message("Error: $ses->{lang}->{lang_login_too_long}") if length($f->{usr_login})>32;
         return $ses->message("Error: Invalid login: reserved word") if $f->{usr_login}=~/^(admin|images|captchas|files)$/;
         return $ses->message("Error: $ses->{lang}->{lang_invalid_login}") unless $f->{usr_login}=~/^[\w\-\_]+$/;
         return $ses->message("Error: $ses->{lang}->{lang_login_exist}")  if $db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$f->{usr_login});
         $db->Exec("UPDATE Users SET usr_login=? WHERE usr_id=?",$f->{usr_login},$ses->getUserId);
      }

      my $pass_check;
      $pass_check = 1 if XUtils::CheckLoginPass($ses, $ses->getUser->{usr_login}, $f->{password_old});
      $pass_check = 1 if !$ses->getUser->{usr_password} || !$ses->getUser->{usr_email};

      if($f->{usr_email} ne $ses->getUser->{usr_email} && !$ses->getUser->{usr_security_lock})
      {
         return $ses->message("Old password required") if !$pass_check;
         return $ses->message("This email already in use") if $db->SelectOne("SELECT usr_id FROM Users WHERE usr_id<>? AND usr_email=?", $ses->getUserId, $f->{usr_email} );
         return $ses->message("Error: Invalid e-mail") unless $f->{usr_email}=~/^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
         $db->Exec("UPDATE Users SET usr_email=? WHERE usr_id=?",$f->{usr_email},$ses->getUserId);
         $f->{msg}.=$ses->{lang}->{lang_email_changed_ok}.'<br>';
         $user->{usr_email_new} = $f->{usr_email};
      }
      if($f->{password_new} && $f->{password_new2} && !$ses->getUser->{usr_security_lock})
      {
         return $ses->message($ses->{lang}->{lang_login_pass_wrong}) if !$pass_check;
         return $ses->message("New password is too short") if length($f->{password_new})<4;
         return $ses->message("New passwords do not match") unless $f->{password_new} eq $f->{password_new2};

         my $hash = XUtils::GenPasswdHash($f->{password_new});
         $db->Exec("UPDATE Users SET usr_password=?, usr_social='' WHERE usr_id=?", $hash, $ses->getUserId );
         $f->{msg}=$ses->{lang}->{lang_pass_changed_ok}.'<br>';
         $user->{usr_password_new} = $f->{password_new};
      }
      unless($ses->getUser->{usr_security_lock})
      {
         if($ses->iPlg('p') && $c->{m_y_interval_days} && $f->{usr_profit_mode} ne $ses->getUser->{usr_profit_mode})
         {
            if($m_y_change_ok)
            {
               $db->Exec("UPDATE Users SET usr_profit_mode_changed=NOW() WHERE usr_id=?",$ses->getUserId);
               $m_y_change_ok=0;
            }
            else
            {
               $f->{usr_profit_mode} ne $ses->getUser->{usr_profit_mode};
            }
         }
         $db->Exec("UPDATE Users 
                    SET usr_pay_email=?, 
                        usr_pay_type=?,
                        usr_profit_mode=?,
                        usr_aff_max_dl_size=?
                    WHERE usr_id=?",$f->{usr_pay_email}||'',
                                 $f->{usr_pay_type}||'',
                                 $f->{usr_profit_mode}||$ses->getUser->{usr_profit_mode}||$c->{m_y_default},
                                 $f->{usr_aff_max_dl_size}||0,
                                 $ses->getUserId);
      }
      $db->Exec("UPDATE Users 
                 SET usr_direct_downloads=?
                 WHERE usr_id=?",$f->{usr_direct_downloads}||0,$ses->getUserId);
      $f->{msg}.=$ses->{lang}->{lang_sett_changed_ok};

      my @custom_fields = qw(
                             twitter_filename
                            );
      push @custom_fields, grep { /_logins$/ } keys(%$f);

      for( @custom_fields )
      {
         $db->Exec("INSERT INTO UserData
                    SET usr_id=?, name=?, value=?
                    ON DUPLICATE KEY UPDATE value=?
                   ",$ses->getUserId, $_, $f->{$_}||'', $f->{$_}||'');
      }

      $ses->ApplyPlugins('user_edit',$user);
   }
   XUtils::CheckAuth($ses);
   my $user = $ses->getUser;
   my $totals = $db->SelectRow("SELECT COUNT(*) as total_files, SUM(file_size) as total_size FROM Files WHERE usr_id=?",$ses->getUserId);
   $totals->{total_size} = sprintf("%.02f",$totals->{total_size}/1024**3);

   my $disk_space = $user->{usr_disk_space} || $c->{disk_space};
   $disk_space = sprintf("%.0f",$disk_space/1024) if $disk_space;
   $user->{premium_expire} = $db->SelectOne("SELECT DATE_FORMAT(usr_premium_expire,'%e %M %Y') FROM Users WHERE usr_id=?",$ses->getUserId);

   if($ses->getUserLimit('bw_limit'))
   {
      $user->{traffic_left} = sprintf("%.0f", $ses->getUserLimit('bw_limit') - $ses->getUserBandwidth($c->{bw_limit_days}));
   }

   my $data = $db->SelectARef("SELECT * FROM UserData WHERE usr_id=?",$user->{usr_id});
   $user->{$_->{name}}=$_->{value} for @$data;

   $user->{usr_money}=~s/\.?0+$//;
   $user->{login_change}=1 if $user->{usr_login}=~/^\d+$/;

   my $referrals = $db->SelectOne("SELECT COUNT(*) FROM Users WHERE usr_aff_id=?",$ses->getUserId);

   my @payout_list = map{ {name=>$_,checked=>($_ eq $ses->getUser->{usr_pay_type})} } split(/\s*\,\s*/,$c->{payout_systems});
   $user->{rsl}=1 if $c->{m_k} && (!$c->{m_k_manual} || $user->{usr_reseller});

   $user->{m_x_on}=1 if ($c->{m_x} && !$c->{m_x_prem}) || ($c->{m_x} && $c->{m_x_prem} && $ses->getUser->{premium});
   if($user->{m_x_on})
   {
      $user->{site_key} = lc $c->{site_url};
      $user->{site_key}=~s/^.+\/\///;
      $user->{site_key}=~s/\W//g;
      $user->{websites} = $db->SelectARef("SELECT * FROM Websites WHERE usr_id=? ORDER BY domain",$ses->getUserId);
   }

   for('m_y','m_y_ppd_dl','m_y_ppd_sales','m_y_pps_dl','m_y_pps_sales','m_y_mix_dl','m_y_mix_sales')
   {
      $user->{$_} = $c->{$_};
   }
   $user->{"usr_profit_mode_$user->{usr_profit_mode}"}=1;
   my $show_password_input = 1 if !$ses->getUser->{usr_password} || !$ses->getUser->{usr_social};

   $ses->PrintTemplate("my_account.html",
                       %{$user},
                       'msg'  => $f->{msg},
                       'remote_url' => $c->{remote_url},
                       %{$totals},
                       'disk_space' => $disk_space,
                       #"pay_type_".$ses->getUser->{usr_pay_type}  => 1,
                       'paypal_email'        => $c->{paypal_email},
                       'payout_list'         => \@payout_list,
                       'alertpay_email'      => $c->{alertpay_email},
                       'webmoney_merchant_id'=> $c->{webmoney_merchant_id},
                       'm_k'  => $c->{m_k},
                       'twit_enable_posting' => $c->{twit_enable_posting},
                       'referrals'           => $referrals,
                       "usr_profit_mode_$user->{usr_profit_mode}" => ' checked',
                       'm_y_change_ok'       => $m_y_change_ok,
                       'token'      => $ses->genToken,
                       'show_password_input' => $show_password_input,
                       'leeches_list' => &getPluginsOptions('Leech', $ses->getUserData() || {}),
                       'leech' => $c->{leech},
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                       'enp_p' => $ses->iPlg('p'),
                       'usr_premium_traffic_mb' => int($user->{usr_premium_traffic} / 2**20),
                      );
}

sub MyReferrals
{
   my $list = $db->SelectARef("SELECT usr_login, usr_created, usr_money, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as dt
                               FROM Users WHERE usr_aff_id=? ORDER BY usr_created DESC".$ses->makePagingSQLSuffix($f->{page}),$ses->getUserId);
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Users WHERE usr_aff_id=?",$ses->getUserId);
   for(@$list)
   {
      $_->{prem}=1 if $_->{dt}>0;
      $_->{usr_money}=~s/\.?0+$//;
   }
   $ses->PrintTemplate("my_referrals.html",
                       list   => $list,
                       paging => $ses->makePagingLinks($f,$total),
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                      );
}

sub CloneFile
{
   my ($file,%opts) = @_;

   my $code = $ses->randchar(12);
   while($db->SelectOne("SELECT file_id FROM Files WHERE file_code=? OR file_real=?",$code,$code)){$code = $ses->randchar(12);}

   $db->Exec("INSERT INTO Files 
        SET usr_id=?, 
            srv_id=?,
            file_fld_id=?,
            file_name=?, 
            file_descr=?, 
            file_public=?, 
            file_code=?, 
            file_real=?, 
            file_real_id=?, 
            file_del_id=?, 
            file_size=?, 
            file_password=?, 
            file_ip=INET_ATON(?), 
            file_md5=?, 
            file_spec=?, 
            file_created=NOW(), 
            file_last_download=NOW()",
         $opts{usr_id}||$ses->getUserId,
         $file->{srv_id},
         $opts{fld_id}||0,
         $file->{file_name},
         '',
         1,
         $code,
         $file->{file_real},
         $file->{file_real_id}||$file->{file_id},
         $file->{file_del_id},
         $file->{file_size},
         $opts{file_password}||'',
         $opts{ip}||$ses->getIP,
         $file->{file_md5},
         $file->{file_spec}||'',
       );
   $db->Exec("UPDATE Servers SET srv_files=srv_files+1 WHERE srv_id=?",$file->{srv_id});
   return $code;
}

sub getTorrents
{
   my (%opts) = @_;
   my $filter_usr_id = "AND t.usr_id=" . int($opts{usr_id}) if $opts{usr_id};
   my $torrents=[];
   if($ses->iPlg('t'))
   {
      $torrents = $db->SelectARef("SELECT *, u.usr_login, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created) as working
                                   FROM Torrents t
                                   LEFT JOIN Users u ON u.usr_id=t.usr_id
                                   WHERE status='WORKING' 
                                   $filter_usr_id
                                   ");
      for my $t (@$torrents)
      {
         my $files = eval { JSON::decode_json($t->{files}) } if $t->{files};
         $t->{file_list} = join('<br>',map{"$_->{path} (<i>".sprintf("%.1f Mb",$_->{size}/1048576)."<\/i>)"} @$files );
         $t->{file_list} =~ s/'/\\'/g;
         $t->{title}=$files->[0]->{path} if $files;
         $t->{title}=~s/\/.+$//;
         $t->{title}=~s/:\d+$//;
         ($t->{done},$t->{total},$t->{down_speed},$t->{up_speed})=split(':',$t->{progress});
         $t->{percent} = sprintf("%.01f", 100*$t->{done}/$t->{total} ) if $t->{total};
         $t->{done} = sprintf("%.1f", $t->{done}/1048576 );
         $t->{total} = sprintf("%.1f", $t->{total}/1048576 );
         $t->{working} = $t->{working}>3600*3 ? sprintf("%.1f hours",$t->{working}/3600) : sprintf("%.0f mins",$t->{working}/60);
         $t->{down_speed} = $ses->makeFileSize($t->{down_speed});
         $t->{up_speed} = $ses->makeFileSize($t->{up_speed});
      }
   }

   return $torrents;
}

sub shorten
{
   my ($str, $max_length) = @_;
   $max_length ||= $c->{display_max_filename};
   return length($str)>$max_length ? substr($str,0,$max_length).'&#133;' : $str
}

sub MyFiles
{
   if($ses->checkToken)
   {
      if($f->{del_code})
      {
         my $file = $db->SelectRow("SELECT * FROM Files WHERE file_code=? AND usr_id=?",$f->{del_code},$ses->getUserId);
         return $ses->message("Security error: not_owner") unless $file;
         $ses->{no_del_log}=1;
         &TrashFiles($file);
         return $ses->redirect("?op=my_files");
      }
      if($f->{del_selected} && $f->{file_id})
      {
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
         return $ses->redirect($c->{site_url}) unless $ids;
         my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)",$ses->getUserId);
         $|=1;
         print"Content-type:text/html\n\n<html><body>\n\n";
         $ses->{no_del_log}=1;
         &TrashFiles(@$files);
         print"<script>window.location='$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}';</script>";
         return;
         return #$ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
      }
      if($f->{del_folder})
      {
         my $fld = $db->SelectRow("SELECT * FROM Folders WHERE usr_id=? AND fld_id=?",$ses->getUserId,$f->{del_folder});
         return $ses->message("Invalid ID") unless $fld;
         $ses->{no_del_log}=1;
         sub delFolder
         {
            my ($fld_id)=@_;
            my $subf = $db->SelectARef("SELECT * FROM Folders WHERE usr_id=? AND fld_parent_id=?",$ses->getUserId,$fld_id);
            for(@$subf)
            {
               &delFolder($_->{fld_id});
            }
            my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_fld_id=?",$ses->getUserId,$fld_id);
            &TrashFiles(@$files);
            &TrashFolder($fld_id);
         }
         &delFolder($f->{del_folder});
         return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
      }
      if(defined $f->{to_folder} && $f->{file_id} && $f->{to_folder_move})
      {
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
         return $ses->redirect($c->{site_url}) unless $ids;
         my $fld_id = $db->SelectOne("SELECT fld_id FROM Folders WHERE usr_id=? AND fld_id=?",$ses->getUserId,$f->{to_folder})||0;
         $db->Exec("UPDATE Files SET file_fld_id=? WHERE usr_id=? AND file_id IN ($ids)",$fld_id,$ses->getUserId);
         return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
      }
      if(defined $f->{to_folder} && $f->{file_id} && $f->{to_folder_copy})
      {
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
         return $ses->redirect($c->{site_url}) unless $ids;
         my $fld_id = $db->SelectOne("SELECT fld_id FROM Folders WHERE usr_id=? AND fld_id=?",$ses->getUserId,$f->{to_folder})||0;
         #$db->Exec("UPDATE Files SET file_fld_id=? WHERE usr_id=? AND file_id IN ($ids)",$fld_id,$ses->getUserId);
         my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)",$ses->getUserId);
         for my $ff (@$files)
         {
            CloneFile($ff,fld_id => $f->{to_folder});
         }
         return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
      }
      if($f->{untrash_selected})
      {
         my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})});
         my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_id IN ($ids)", $ses->getUserId);
         &UntrashFiles(@$files);
         return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=-1");
      }
   }
   if($f->{set_flag} && $f->{'file_id[]'})
   {
       my @file_ids = @{ &ARef($f->{'file_id[]'}) };
       my $name = $1 if $f->{set_flag} =~ /^(file_public|file_premium_only)$/;
       $db->Exec("UPDATE Files SET $name=? WHERE usr_id=? AND file_id IN (".join(',',@file_ids).")",
                     $f->{value} eq 'true' ? 1 : $f->{value},
                     $ses->getUserId,
                     );
       print "Content-type: text\plain\n\nOK";
       return;
   }
   if($f->{create_new_folder})
   {
       $f->{create_new_folder} = $ses->SecureStr($f->{create_new_folder});
       return $ses->message("Invalid folder name!") unless $f->{create_new_folder};
       return $ses->message("Invalid parent folder") if $f->{fld_id} && !$db->SelectOne("SELECT fld_id FROM Folders WHERE usr_id=? AND fld_id=?",$ses->getUserId,$f->{fld_id});
       return $ses->message("You have can't have more than 1024 folders") if $db->SelectOne("SELECT COUNT(*) FROM Folders WHERE usr_id=?",$ses->getUserId)>=1024;
       $db->Exec("INSERT INTO Folders SET usr_id=?, fld_parent_id=?, fld_name=?",$ses->getUserId,$f->{fld_id},$f->{create_new_folder});
       return $ses->redirect("$c->{site_url}/?op=my_files&fld_id=$f->{fld_id}");
   }
   if($f->{add_my_acc})
   {
      my @file_codes = map { /\/(\w{12})/ } split("\n", $f->{url_mass});
      $file_codes[0] ||= $f->{add_my_acc};
      my $ids = join("','",grep{/^\w+$/} @file_codes);
      my $files = $db->SelectARef("SELECT * FROM Files
                        WHERE file_code IN ('$ids')");
      my $fld_id = $db->SelectOne("SELECT fld_id FROM Folders WHERE fld_id=? AND usr_id=?",
                        $f->{to_folder},
                        $ses->getUserId);
      for(@$files) {
          $_->{file_status} = "non-public file" if !$_->{file_public};
         next if $_->{file_status};
         $_->{file_password} ||= $f->{link_pass};
         my $total_size = $db->SelectOne("SELECT SUM(file_size) FROM Files WHERE usr_id=?",
                        $ses->getUserId);
         if(!$c->{disk_space} || $c->{disk_space} && $total_size + $_->{file_size} < $c->{disk_space} * 2**20)
         {
            $_->{file_code_new} = CloneFile($_,
                           fld_id => $fld_id||0,
                           file_password => $_->{file_password}||'');
            $_->{file_status} ||= 'OK';
         }
         else
         {
            $_->{file_status} ||= 'Disk quota exceeded';
         }
      }
      
      # Case 1: the files were added through upload form
      if($f->{url_mass}) {
         my @har;
         push @har, { name => 'op', value => 'upload_result' };
         push @har, { name => 'link_rcpt', value => $f->{link_rcpt} } if $f->{link_rcpt};
         for(@$files) {
            push @har, { name => 'fn', value => $_->{file_code_new} || $_->{file_name} };
            push @har, { name => 'st', value => $_->{file_status}||'OK' };
         }
         print "Content-type: text/html\n\n";
         print"<HTML><BODY><Form name='F1' action='' method='POST'>";
         print"<input type='hidden' name='$_->{name}' value='$_->{value}'>" for @har;
         print"</Form><Script>document.location='javascript:false';document.F1.submit();</Script></BODY></HTML>";
         return;
      }

      # Case 2: the files were added through AJAX
      my @has_errors = grep { $_->{file_status} ne 'OK' } @$files;
      print"Content-type:text/html\n\n";
      print @has_errors ? $has_errors[0]->{file_status} : $ses->{lang}->{lang_added_to_account};
      return;
   }
   if($f->{del_torrent})
   {
      my $torr = $db->SelectRow("SELECT * FROM Torrents WHERE sid=? AND usr_id=?",$f->{del_torrent},$ses->getUserId);
      return $ses->redirect("$c->{site_url}/?op=my_files") unless $torr;
      my $res = $ses->api2($torr->{srv_id},{
                                  op   => 'torrent_delete',
                                  sid  => $f->{del_torrent},
                                 });
      return $ses->message("Error1:$res") unless $res eq 'OK';

      $db->Exec("DELETE FROM Torrents WHERE sid=? AND status='WORKING'",$f->{del_torrent});
      return $ses->redirect("$c->{site_url}/?op=my_files")
   }

   if($f->{torrents})
   {
      my $t = $ses->CreateTemplate('my_files_torrents.html');
      $t->param(torrents => &getTorrents(usr_id => $ses->getUserId));
      return print "Content-type: text/html\n\n", $t->output;
   }

   $f->{sort_field}||='file_created';
   $f->{sort_order}||='down';
   $f->{fld_id}||=0;
   my ($files,$total);
   my $folders=[];
   my $curr_folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=?",$f->{fld_id}) if $f->{fld_id};
   $curr_folder ||= {};
   return $ses->message("Invalid folder id") if $f->{fld_id} > 0 && $curr_folder->{usr_id}!=$ses->getUserId;

   $f->{key} = $f->{term} if $f->{term}; # autocomplete
   my $filter_key = "AND (file_name LIKE '%$1%' OR file_descr LIKE '%$1%')" if $f->{key} =~ /([^'\\]+)/;
   my $filter_trash = "AND f.file_trashed" . ($f->{fld_id} == -1 ? " > 0" : " = 0");
   my $filter_fld = "AND f.file_fld_id='$1'" if !$filter_key && $f->{fld_id} >= 0 && $f->{fld_id} =~ /^(\d+)$/;
   my $filter_trashed_folder = "AND fld_trashed" . ($f->{fld_id} == -1 ? " > 0" : " = 0");

   my $files = $db->SelectARef("SELECT f.*, DATE(f.file_created) as created, 
                                (SELECT COUNT(*) FROM Comments WHERE cmt_type=1 AND file_id=cmt_ext_id) as comments,
                                DATE(file_created) AS file_date,
                                UNIX_TIMESTAMP(file_trashed) as trashed_at
                                FROM Files f 
                                WHERE f.usr_id=? 
                                $filter_fld
                                $filter_key
                                $filter_trash
                                ".&makeSortSQLcode($f,'file_created').$ses->makePagingSQLSuffix($f->{page}),$ses->getUserId);

   my $files_total = $db->SelectOne("SELECT COUNT(*) FROM Files f
                                WHERE usr_id=?
                                $filter_fld
                                $filter_key
                                $filter_trash",
                                $ses->getUserId);

   my $folders = $db->SelectARef("SELECT f.*, COUNT(ff.file_id) as files_num
                                  FROM Folders f
                                  LEFT JOIN Files ff ON f.fld_id=ff.file_fld_id
                                  WHERE f.usr_id=? 
                                  AND fld_parent_id=?
                                  $filter_trashed_folder
                                  GROUP BY fld_id
                                  ORDER BY fld_name".$ses->makePagingSQLSuffix($f->{page}),$ses->getUserId,$f->{fld_id});

   my $folders_total = $db->SelectOne("SELECT COUNT(*) FROM Folders f
                                WHERE usr_id=?
                                AND f.fld_parent_id=?
                                $filter_trashed_folder
                                ",
                                $ses->getUserId,
                                $f->{fld_id}||0);


   my %sort_hash = &makeSortHash($f,['file_name','file_downloads','comments','file_size','file_public','file_created','file_premium_only']);

   my $totals = $db->SelectRow("SELECT COUNT(*) as total_files, SUM(file_size) as total_size FROM Files WHERE usr_id=?",$ses->getUserId);

   for(@$folders)
   {
      $_->{fld_name_txt} = length($_->{fld_name})>25 ? substr($_->{fld_name},0,25).'&#133;' : $_->{fld_name};
      $_->{files_total} = $ses->getFilesTotal($_->{fld_id}, "AND !file_trashed");
   }

   my $trashed = $db->SelectARef("SELECT * FROM Files WHERE usr_id=? AND file_trashed > 0", $ses->getUserId);
   unshift @$folders, { fld_id => -1, fld_name_txt => 'Trash', files_total => int(@$trashed), trash => 1 } if !$f->{fld_id} && @$trashed > 0;
   unshift @$folders, { fld_id=>$curr_folder->{fld_parent_id},fld_name_txt=>'&nbsp;. .&nbsp;'} if $f->{fld_id};

   my $current_time = $db->SelectOne("SELECT UNIX_TIMESTAMP()");

   for(@$files)
   {
      $_->{site_url} = $c->{site_url};
      $_->{file_size} = $ses->makeFileSize($_->{file_size});
      my $file_descr = $_->{file_descr};
      utf8::decode($file_descr);
      $_->{file_descr} = length($file_descr)>48 ? substr($file_descr,0,48).'&#133;' : $file_descr;
      utf8::encode($_->{file_descr});
      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = &shorten($file_name, $c->{display_max_filename});
      utf8::encode($_->{file_name_txt});
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_downloads}||='';
      $_->{comments}||='';
      $_->{time_left} = &timediff($current_time, $_->{trashed_at} + $c->{trash_expire} * 3600)
         if $_->{trashed_at};
   }

   sub timediff
   {
      my $interval = $_[1] - $_[0];
      return int($interval / 3600) . " hours" if $interval > 3600;
      return int($interval / 60) . " minutes" if $interval > 60;
      return $interval . " seconds";
   }

   my @folders_tree = &buildFoldersTree(usr_id => $ses->getUserId);

   my $torrents = &getTorrents(usr_id => $ses->getUserId);

   my $smartp=1 if $ses->iPlg('p') && $c->{m_p_premium_only};

   my $total_size = $db->SelectOne("SELECT SUM(file_size) FROM Files WHERE usr_id=?",
         $ses->getUserId);
   my $disk_space = ($ses->{user}->{usr_disk_space} || $c->{disk_space}) * 2**20;
   my $occupied_percent = min(100, int($total_size * 100 / $disk_space)) if $disk_space;


   if($f->{load} eq 'folders')
   {
      $ses->{form}->{no_hdr} = 1;
      $ses->PrintTemplate('folders.html',
         'current_folder'   => &shorten($curr_folder->{fld_name}||''),
         'current_fld_id'   => $curr_folder ? $curr_folder->{fld_id} : '',
         'fld_descr'        => $curr_folder->{fld_descr},
         'folders'          => $folders,
         'token'            => $ses->genToken,
      );
      return;
   }

   if($f->{load} eq 'files')
   {
      $ses->{form}->{no_hdr} = 1;
      $ses->PrintTemplate('files.html',
         files          => $files,
         'token'        => $ses->genToken,
         'folders_tree' => \@folders_tree,
         'current_fld_id'   => $curr_folder ? $curr_folder->{fld_id} : '',
         trash => $f->{fld_id} < 0 ? 1 : 0,
         %sort_hash,
         );
      return;
   }

   if($f->{term})
   {
      my %ret;
      $ret{$_->{file_name}} = 1 for @$files;
      return &SendJSON([ sort keys(%ret) ]);
   }

   my $current_folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=?", $f->{fld_id});

   $totals->{total_size} = $ses->makeFileSize($totals->{total_size});
   $disk_space = $disk_space ? $ses->makeFileSize($disk_space) : 'Unlimited';

   $ses->PrintTemplate("my_files.html",
                       'files'         => $files,
                       'folders'       => $folders,
                       'folders_tree'  => \@folders_tree,
                       'folder_id'     => $f->{fld_id},
                       'folder_name'   => &shorten($curr_folder->{fld_name}),
                       'fld_descr'     => $curr_folder->{fld_descr},
                       'key'           => $f->{key},
                       'disk_space'    => $disk_space,
                       'deleted_num'   => $db->SelectOne("SELECT COUNT(*) FROM FilesDeleted WHERE usr_id=? AND hide=0",$ses->getUserId),
                       'per_page'      => $f->{per_page}||$c->{items_per_page}||5,
                       'current_folder'   => &shorten($curr_folder->{fld_name}||'', 30),
                       'torrents'      => $torrents,
                       'smartp'        => $smartp,
                       'enable_file_comments' => $c->{enable_file_comments},
                       'token'      => $ses->genToken,
                       'occupied_percent' => $occupied_percent||0,
                       'current_fld_id'   => $curr_folder ? $curr_folder->{fld_id} : '',
                       'trash' => $f->{fld_id} < 0 ? 1 : 0,
                       'folders_total'    => $folders_total,
                       'files_total'      => $files_total,
                       %{$totals},
                       %sort_hash,
                      );
}

sub MyFilesDeleted
{
    if($f->{hide})
    {
        $db->Exec("UPDATE FilesDeleted SET hide=1 WHERE usr_id=?",$ses->getUserId);
        return $ses->redirect("?op=my_files_deleted");
    }
    my $files = $db->SelectARef("SELECT *, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(deleted) as ago
                                 FROM FilesDeleted 
                                 WHERE usr_id=?
                                 AND hide=0 
                                 ORDER BY deleted DESC",$ses->getUserId);
    for(@$files)
    {
        $_->{ago} = sprintf("%.0f",$_->{ago}/60);
        $_->{ago} = $_->{ago}<180 ? "$_->{ago} mins" : sprintf("%.0f hours",$_->{ago}/60)
    }
    $ses->PrintTemplate("my_files_deleted.html",
                        files => $files,
                       );
}

sub buildTree
{
   my ($fh,$parent,$depth)=@_;
   my @tree;
   for my $x (@{$fh->{$parent}})
   {
      $x->{pre}='&nbsp;&nbsp;'x$depth;
      push @tree, $x;
      push @tree, &buildTree($fh,$x->{fld_id},$depth+1);
   }
   return @tree;
}

sub buildFoldersTree
{
   my (%opts) = @_;
   my $allfld = $db->SelectARef("SELECT * FROM Folders WHERE usr_id=? AND !fld_trashed ORDER BY fld_name",$opts{usr_id});
   my $fh;
   push @{$fh->{$_->{fld_parent_id}}},$_ for @$allfld;
   return( &buildTree($fh,0,0) );
}

sub MyFilesExport
{
   my $filter;
   if($f->{"file_id[]"})
   {
      my $ids = join ',', grep{/^\d+$/}@{ARef($f->{"file_id[]"})};
      $filter="AND file_id IN ($ids)" if $ids;
   }
   else
   {
      $filter="AND file_fld_id='$f->{fld_id}'" if $f->{fld_id}=~/^\d+$/;
   }
   my $list = $db->SelectARef("SELECT * FROM Files f, Servers s
                               WHERE usr_id=? 
                               AND f.srv_id=s.srv_id
                               $filter 
                               ORDER BY file_name",$ses->getUserId);
   print $ses->{cgi_query}->header( -type    => 'text/html',
                                    -expires => '-1d',
                                    -charset => $c->{charset});
   my (@list,@list_bb,@list_html);
   for my $file (@$list)
   {
      $file->{download_link} = $ses->makeFileLink($file);
      if($c->{m_i} && $file->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i)
      {
         $ses->getThumbLink($file);
      }
      else
      {
         $file->{fsize} = $ses->makeFileSize($file->{file_size});
      }
      push @list, $file->{download_link};
      push @list_bb, $file->{thumb_url} ? "[URL=$file->{download_link}][IMG]$file->{thumb_url}\[\/IMG]\[\/URL]" : "[URL=$file->{download_link}]$file->{file_name} - $file->{fsize}\[\/URL]";
      push @list_html, $file->{thumb_url} ? qq[<a href="$file->{download_link}" target=_blank><img src="$file->{thumb_url}" border=0><\/a>"] : qq[<a href="$file->{download_link}" target=_blank>$file->{file_name} - $file->{fsize}<\/a>];
   }
   print"<HTML><BODY style='font: 13px Arial;'>";
   print"<b>Download links</b><br><textarea cols=100 rows=5 wrap=off>".join("\n",@list)."<\/textarea><br><br>";
   print"<b>Forum code</b><br><textarea cols=100 rows=5 wrap=off>".join("\n",@list_bb)."<\/textarea><br><br>";
   print"<b>HTML code</b><br><textarea cols=100 rows=5 wrap=off>".join("\n",@list_html)."<\/textarea><br><br>";
   return;
}

sub UserPublic
{
   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_login=?",$f->{usr_login});
   return $ses->message("No such user exist") unless $user;
   $f->{fld}=~s/\///g;
   my $folder = $db->SelectRow("SELECT * FROM Folders WHERE usr_id=? AND fld_id=?",$user->{usr_id},$f->{fld_id});
   return $ses->message("No such folder") if $f->{fld} && !$folder;
   my $files = $db->SelectARef("SELECT *, TO_DAYS(CURDATE())-TO_DAYS(file_created) as created,
                                       s.srv_htdocs_url
                                FROM Files f, Servers s
                                WHERE usr_id=?
                                AND file_public=1
                                AND file_fld_id=?
                                AND f.srv_id=s.srv_id
            ORDER BY file_created DESC".$ses->makePagingSQLSuffix($f->{page}),$user->{usr_id},$folder->{fld_id}||0);

   my $total = $db->SelectOne("SELECT COUNT(*)
                                FROM Files f, Servers s
                                WHERE usr_id=?
                                AND file_public=1
                                AND file_fld_id=?
                                AND f.srv_id=s.srv_id
                                 ORDER BY file_created DESC",$user->{usr_id},$folder->{fld_id}||0);

   my $folders = $db->SelectARef("SELECT *
                                  FROM Folders
                                  WHERE usr_id=?
                                  AND fld_parent_id=?
                                  ORDER BY fld_name".$ses->makePagingSQLSuffix($f->{page}),$user->{usr_id},$folder->{fld_id}||0);
   my $parent = $db->SelectRow("SELECT fld_id as fld_parent_id, fld_name as parent_name 
                                FROM Folders 
                                WHERE usr_id=? AND fld_id=?",$user->{usr_id},$folder->{fld_parent_id}) if $folder->{fld_parent_id};
   my $cx;
   for(@$files)
   {
      $_->{site_url} = $c->{site_url};

      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = length($file_name)>$c->{display_max_filename} ? substr($file_name,0,$c->{display_max_filename}).'&#133;' : $file_name;
      utf8::encode($_->{file_name_txt});

      $_->{file_size}     = $ses->makeFileSize($_->{file_size});
      $_->{download_link} = $ses->makeFileLink($_);
      my ($ext) = $_->{file_name}=~/\.(\w+)$/i;
      $ext=lc $ext;
#      $_->{img_preview} = $ext=~/^(ai|aiff|asf|avi|bmpbz2|css|doc|eps|gif|gz|html|jpg|jpeg|mid|mov|mp3|mpg|mpeg|ogg|pdf|png|ppt|ps|psd|qt|ra|ram|rm|rpm|rtf|tgz|tif|torrent|txt|wav|xls|xml|zip|exe|flv|swf|qma|wmv|mkv)$/i ? "$c->{site_url}/images/icons/$ext-dist.png" : "$c->{site_url}/images/icons/1.gif";
      $_->{img_preview} = $ext=~/^(ai|aiff|asf|avi|bmpbz2|css|doc|eps|gif|gz|html|jpg|jpeg|mid|mov|mp3|mpg|mpeg|ogg|pdf|png|ppt|ps|psd|qt|ra|ram|rm|rpm|rtf|tgz|tif|torrent|txt|wav|xls|xml|zip|7z|exe|flv|swf|qma|wmv|mkv|rar)$/ ? "$c->{site_url}/images/icons/$ext-dist.png" : "$c->{site_url}/images/icons/default-dist.png";
      $_->{add_to_account}=1 if $ses->getUser && $_->{usr_id}!=$ses->getUserId;
      if( ($c->{m_i} && $_->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i )
          || ($c->{m_v} && $_->{file_name}=~/\.(avi|divx|flv|mp4|wmv|mkv)$/i) )
      {
         my $iurl = $_->{srv_htdocs_url};
         $iurl=~s/^(.+)\/.+$/$1\/i/;
         my $dx = sprintf("%05d",($_->{file_real_id}||$_->{file_id})/$c->{files_per_folder});
         $_->{img_preview2} = "$iurl/$dx/$_->{file_real}_t.jpg";
      }
      $_->{'tr'}=1 if ++$cx%3==0;
   }
   for(@$folders)
   {
      $_->{site_url} = $c->{site_url};
      $_->{usr_login} = $f->{usr_login};
   }
   $ses->{page_title} = $ses->{lang}->{lang_files_of}." ".$user->{usr_login};
   $ses->{page_title} .= ": $folder->{fld_name} folder" if $folder->{fld_name};
   $ses->{meta_descr} = $user->{usr_login}.' '.$ses->{lang}->{lang_files};

   if($f->{load} eq 'folders')
   {
      $ses->{form}->{no_hdr} = 1;
      $ses->PrintTemplate('user_public_folders.html',
            %$parent,
            'fld_id'  => $f->{fld_id},
            'folders' => $folders,
         );
      return;
   }

   if($f->{load} eq 'files')
   {
      $ses->{form}->{no_hdr} = 1;
      $ses->PrintTemplate('user_public_files.html',
            files => $files,
         );
      return;
   }

   $ses->PrintTemplate("user_public.html", 
                       'login'   => $user->{usr_login},
                       'folders' => $folders,
                       'fld_id'  => $f->{fld_id},
                       'paging' => $ses->makePagingLinks($f,$total),
                       'files_total' => $total,
                       'per_page' => $c->{items_per_page},
                       'folders_total' => $db->SelectOne("SELECT COUNT(*) FROM Folders WHERE usr_id=?", $ses->getUserId),
                       %$parent,
                       files => $files );
}

sub FileEdit
{
   my $adm_mode = 1 if $f->{op} =~ /^admin_/;
   my $redirect_op = $adm_mode ? 'admin_files' : 'my_files';
   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?",$f->{file_id});
   $file ||= $db->SelectRow("SELECT * FROM Files WHERE file_code=?",$f->{file_code});
   return $ses->message("No such file!") unless $file;
   return $ses->message("It's not your file!") if !$adm_mode && $file->{usr_id}!=$ses->getUserId;

   if($c->{rar_info} && $f->{rar_pass_remove})
   {
         my $res = $ses->api2($file->{srv_id},
                             {
                                op        => 'rar_password',
                                file_id   => $file->{file_real_id}||$file->{file_id},
                                file_code => $file->{file_real},
                                rar_pass  => $f->{rar_pass},
                                file_name => $file->{file_name},
                             }
                            );
         unless($res=~/Software error/i)
         {
          $db->Exec("UPDATE Files SET file_spec=? WHERE file_real=?",$res,$file->{file_real});
         }
         return $ses->redirect("?op=$f->{op}&file_code=$file->{file_code}");
   }
   if($c->{rar_info} && $f->{rar_files_delete} && $f->{fname})
   {
         my $res = $ses->api2($file->{srv_id},
                             {
                                op        => 'rar_file_del',
                                file_name => $file->{file_name},
                                file_id   => $file->{file_real_id}||$file->{file_id},
                                file_code => $file->{file_real},
                                rar_pass  => $f->{rar_pass},
                                files     => JSON::encode_json(&ARef($f->{fname})),
                             }
                            );
         unless($res=~/Software error/i)
         {
          $db->Exec("UPDATE Files SET file_spec=? WHERE file_real=?",$res,$file->{file_code});
         }
         else
         {
          return $ses->message($res);
         }
         return $ses->redirect("?op=$f->{op}&file_code=$file->{file_code}");
   }
   if($c->{rar_info} && $f->{rar_files_extract} && $f->{fname})
   {
         my $files = join ' ', map{qq["$_"]} @{&ARef($f->{fname})};
         my $res = $ses->api2($file->{srv_id},
                             {
                                op        => 'rar_file_extract',
                                file_name => $file->{file_name},
                                file_id   => $file->{file_real_id}||$file->{file_id},
                                file_code => $file->{file_real},
                                rar_pass  => $f->{rar_pass},
                                files     => $files,
                                files     => JSON::encode_json(&ARef($f->{fname})),
                                usr_id    => $ses->getUserId,
                             }
                            );
         return $ses->message($res) unless $res eq 'OK';
         return $ses->redirect("?op=$redirect_op");
   }
   if($c->{rar_info} && $f->{rar_split} && $f->{part_size}=~/^[\d\.]+$/)
   {
         $f->{part_size}*=1024;
         my $res = $ses->api2($file->{srv_id},
                             {
                                op        => 'rar_split',
                                file_id   => $file->{file_real_id}||$file->{file_id},
                                file_code => $file->{file_real},
                                rar_pass  => $f->{rar_pass},
                                part_size => "$f->{part_size}k",
                                usr_id    => $ses->getUserId,
                                file_name => $file->{file_name},
                             }
                            );
         return $ses->message($res) unless $res eq 'OK';
         return $ses->redirect("?op=$redirect_op");
   }
   if($f->{save})
   {
      return $ses->redirect($c->{site_url}) if !&CheckReferer($ENV{HTTP_REFERER});
      $f->{file_name}=~s/%(\d\d)/chr(hex($1))/egs;
      $f->{file_name}=~s/%/_/gs;
      $f->{file_name}=~s/\s{2,}/ /gs;
      $f->{file_name}=~s/[\#\"]+/_/gs;
      $f->{file_name}=~s/[^\w\d\.-]/_/g if $c->{sanitize_filename};
      return $ses->message("Filename have unallowed extension") if ($c->{ext_allowed} && $f->{file_name}!~/\.($c->{ext_allowed})$/i) || ($c->{ext_not_allowed} && $f->{file_name}=~/\.($c->{ext_not_allowed})$/i);
      $f->{file_descr} = $ses->SecureStr($f->{file_descr});
      $f->{file_password} = $ses->SecureStr($f->{file_password});
      return $ses->message("Filename too short") if length($f->{file_name})<3;
      $db->Exec("UPDATE Files SET file_name=?, file_descr=?, file_public=?, file_password=?, file_premium_only=? WHERE file_id=?",$f->{file_name},$f->{file_descr},$f->{file_public},$f->{file_password},$f->{file_premium_only},$file->{file_id});
      if($adm_mode)
      {
        $db->Exec("UPDATE Files SET file_code=? WHERE file_id=?", $f->{file_code}, $file->{file_id});
        return $ses->redirect("?op=admin_files;fld_id=$file->{file_fld_id}");
      }
      return $ses->redirect("?op=$redirect_op;fld_id=$file->{file_fld_id}");
   }

   if($file->{file_name}=~/\.(rar|zip|7z)$/i && $file->{file_spec} && $c->{rar_info})
   {
      $file->{rar_nfo}=$file->{file_spec};
      $file->{rar_nfo}=~s/\r//g;
      $file->{rar_password}=1 if $file->{rar_nfo}=~s/password protected\n//ie;
      $file->{rar_nfo}=~s/\n\n.+$//s;
      my @files;
      my $fld;
      $file->{file_spec} =~ s/\r//g;
      while($file->{file_spec}=~/^(.+?) - ([\d\.]+) (KB|MB)$/gim)
      {
         my $path=$1;
         my $fname=$1;
         my $fsize = "$2 $3";
         if($fname=~s/^(.+)\///)
         {
            #push @rf,"<b>$1</b>" if $fld ne $1;
            push @files, {fname=>$1, fname2=>"<b>$1</b>"} if $fld ne $1;;
            $fld = $1;
         }
         else
         {
            $fld='';
         }
         $fname=" &nbsp; &nbsp; $fname" if $fld;
         push @files, {fname=>$path, fname2=>"$fname - $fsize"};
      }
      #$file->{rar_nfo}.=join "\n", @rf;
      $file->{rar_files} = \@files;
   }

   $file->{file_size2} = sprintf("%.0f",$file->{file_size}/1048576);
   $file->{smartp}=1 if $ses->iPlg('p') && $c->{m_p_premium_only};

   $ses->PrintTemplate("file_form.html",
                        %{$file},
                        op => $f->{op},
                        adm_mode => $adm_mode||0,
                        'token'      => $ses->genToken,
                        );
}

sub FolderEdit
{
   my $folder = $db->SelectRow("SELECT * FROM Folders WHERE fld_id=? AND usr_id=?",$f->{fld_id},$ses->getUserId);
   return $ses->message("No such folder!") unless $folder;
   if($f->{save})
   {
      $f->{fld_name}  = $ses->SecureStr($f->{fld_name});
      $f->{fld_descr} = $ses->SecureStr($f->{fld_descr});
      return $ses->message("Folder name too short") if length($f->{fld_name})<3;
      $db->Exec("UPDATE Folders SET fld_name=?, fld_descr=? WHERE fld_id=?",$f->{fld_name},$f->{fld_descr},$f->{fld_id});
      return $ses->redirect("?op=my_files");
   }
   $ses->PrintTemplate("folder_form.html", %{$folder} );
}

sub getAffiliate
{
   my $usr_id = $ses->getUser ? $ses->getUserId : 0;

   my $aff_id;
   $aff_id = $ses->getCookie('aff')||0;
   $aff_id = 0 if $aff_id==$usr_id;
   $aff_id = $ses->getUser->{usr_aff_id} if $ses->getUser && $ses->getUser->{usr_aff_id} && !$aff_id;
   return($aff_id||0);
}

sub Payments
{
   return $ses->redirect($c->{site_url}) unless $c->{enabled_prem};

   if(my $file = $db->SelectRow("SELECT * FROM Files WHERE file_code=?", $ENV{HTTP_REFERER} =~ /\/(\w{12})/))
   {
      $ses->setCookie("aff",$file->{usr_id},'+14d');
   }

   if($c->{no_anon_payments} && !$ses->getUser)
   {
      return $ses->redirect("$c->{site_url}/?op=registration&next=payments-$f->{type}-$f->{amount}");
   }

   if($f->{amount})
   {
      $f->{amount}=sprintf("%.02f",$f->{amount});

      return $ses->message("You're not a reseller!") if $c->{m_k_manual} && $f->{reseller} && !$ses->getUser->{usr_reseller};
      $f->{referer}='RESELLER' if $f->{reseller};

      my %opts = %{$f};
      $opts{target} = $f->{target}||'premium_days';
      $opts{target} = 'reseller' if $f->{reseller};

      $opts{usr_id} = $ses->getUser ? $ses->getUserId : 0;
      $opts{aff_id} = &getAffiliate();
      $opts{referer} ||= $ses->getCookie('ref_url') || $ENV{HTTP_REFERER} || '';
      $opts{email} = $ses->getUser->{usr_email} if $ses->getUser;
      $opts{days} = $ses->ParsePlans($c->{payment_plans}, 'hash')->{$f->{amount}} if $opts{target} eq 'premium_days';;
      $opts{traffic} = $ses->ParsePlans($c->{traffic_plans}, 'hash')->{$f->{amount}} if $opts{target} eq 'premium_traffic';;

      return $ses->message("Invalid payment amount") if $opts{target} eq 'premium_days' && !$opts{days};
      return $ses->message("Invalid payment amount") if $opts{target} eq 'premium_traffic' && !$opts{traffic};

      require IPN;
      my $transaction = IPN->new($ses)->createTransaction(%opts);
      $f->{id} = $transaction->{id};
      $f->{email} = $ses->getUser->{usr_email} if $ses->getUser;
      $ses->setCookie('transaction_id', $transaction->{id});
      my $url = $ses->getPlugins('Payments')->checkout($f) || return $ses->message("No appropriate plugin");
      
      # Some APIs aren't allowing to pass the transaction ID with Return URL
      return $ses->redirect($url) if $url && !$f->{no_redirect};
   }

   # Do not modify $c directly to prevent affecting FastCGI
   my $limits = { %$c };
   for my $x ('max_upload_filesize')
   {
      for my $y ('anon','reg','prem')
      {
         my $z = "$x\_$y";
         $limits->{$z} = $c->{$z} ? "$c->{$z} Mb" : "Unlimited";
      }
   }
   $limits->{max_downloads_number_reg} = $c->{max_downloads_number_reg}||'Unlimited';
   $limits->{max_downloads_number_prem} = $c->{max_downloads_number_prem}||'Unlimited';
   $limits->{files_expire_anon} = $c->{files_expire_access_anon} ? "$c->{files_expire_access_anon} $ses->{lang}->{lang_days_after_downl}" : $ses->{lang}->{lang_never};
   $limits->{files_expire_reg}  = $c->{files_expire_access_reg}  ? "$c->{files_expire_access_reg} $ses->{lang}->{lang_days_after_downl}" : $ses->{lang}->{lang_never};
   $limits->{files_expire_prem} = $c->{files_expire_access_prem} ? "$c->{files_expire_access_prem} $ses->{lang}->{lang_days_after_downl}" : $ses->{lang}->{lang_never};

   $limits->{disk_space_reg} = $c->{disk_space_reg} ? sprintf("%.0f GB",$c->{disk_space_reg}/1024) : "Unlimited";
   $limits->{disk_space_prem} = $c->{disk_space_prem} ? sprintf("%.0f GB",$c->{disk_space_prem}/1024) : "Unlimited";

   $limits->{bw_limit_anon} = $c->{bw_limit_anon} ? sprintf("%.0f GB",$c->{bw_limit_anon}/1024)." in $c->{bw_limit_days} $ses->{lang}->{lang_days}" : 'Unlimited';
   $limits->{bw_limit_reg}  = $c->{bw_limit_reg}  ? sprintf("%.0f GB",$c->{bw_limit_reg}/1024)." in $c->{bw_limit_days} $ses->{lang}->{lang_days}" : 'Unlimited';
   $limits->{bw_limit_prem} = $c->{bw_limit_prem} ? sprintf("%.0f GB",$c->{bw_limit_prem}/1024)." in $c->{bw_limit_days} $ses->{lang}->{lang_days}" : 'Unlimited';
   for my $utype (qw(anon reg prem))
   {
      $limits->{"download_resume_$utype"} = $c->{m_n} ? $c->{"m_n_dl_resume_$utype"} : $c->{"direct_links_$utype"}
   }

   require Time::Elapsed;
   my $et = new Time::Elapsed;
   my @payment_types = $ses->getPlugins('Payments')->get_payment_buy_with;
   my @plans =  @{ $ses->ParsePlans($c->{payment_plans}, 'array') };
   my @traffic_packages =  @{ $ses->ParsePlans($c->{traffic_plans}, 'array') };
   for(@plans, @traffic_packages)
   {
      $_->{payment_types} = \@payment_types;
   }

   $ses->PrintTemplate("payments.html",
                        %{$limits},
                        payment_types => \@payment_types,
                        plans => \@plans,
                        premium => $ses->getUser && $ses->getUser->{premium},
                        expire_elapsed => $ses->getUser && $et->convert($ses->getUser->{exp_sec}),
                        'rand' => $ses->randchar(6),
                        ask_email => $utype eq 'anon' && !$c->{no_anon_payments},
                        monthprice => &computeMonthlyPrice(@plans),
                        'currency_symbol' => ($c->{currency_symbol}||'$'),
                        'traffic_packages' => \@traffic_packages,
                      );
}

sub computeMonthlyPrice
{
   my @sorted = sort { abs($a->{day}-30) <=> abs($b->{day}-30) } @_;
   return sprintf("%d", 30 * $sorted[0]->{amount} / $sorted[0]->{days});
}

sub PaymentComplete
{
   my $str = shift;
   my ($id,$usr_id)=split(/-/,uri_unescape($str));
   ($id,$usr_id) = split(/-/,$ses->getCookie('transaction_id')) if !$id;
   my $trans = $db->SelectRow("SELECT *, INET_NTOA(ip) as ip, (UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created)) as dt
                               FROM Transactions 
                               WHERE id=?",$id) if $id;
   return $ses->message("No such transaction exist") unless $trans;
   return $ses->message("Internal error") unless $trans->{ip} eq $ENV{REMOTE_ADDR};
   return $ses->message("Your account created successfully.<br>Please check your e-mail for login details") if $trans->{dt}>3600;
   return $ses->message("Your payment have not verified yet.<br>Please refresh this page in 1-3 minutes") unless $trans->{verified};

   my $user = $db->SelectRow("SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
                              FROM Users 
                              WHERE usr_id=?",$trans->{usr_id});
   require Time::Elapsed;
   my $et = new Time::Elapsed;
   my $exp = $et->convert($user->{exp_sec});
   $ses->PrintTemplate('message.html',
                  err_title => 'Payment completed',
            msg => "Your payment processed successfully!<br>You should receive your password on e-mail in few minutes.<br><br>Login: $user->{usr_login}<br>Password: ******<br><br>Your premium account expires in:<br>$exp",
         );
}

sub AdminUsersAdd
{
   my ($list,$result);
   if($f->{generate})
   {
      my @arr;
      $f->{prem_days}||=0;
      for(1..$f->{num})
      {
         my $login = join '', map int rand 10, 1..7;
         while($db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$login)){ $login = join '', map int rand 10, 1..7; }
         my $password = $ses->randchar(10);
         push @arr, "$login:$password:$f->{prem_days}";
      }
      $list = join "\n", @arr;
   }
   if($f->{create} && $f->{list})
   {
      my @arr;
      $f->{list}=~s/\r//gs;
      for( split /\n/, $f->{list} )
      {
         return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
         #my ($login,$password,$days) = /^([\w\-\_]+):(\w+):(\d+)$/;
         my ($login,$password,$days,$email) = split(/:/,$_);
         next unless $login=~/^[\w\-\_]+$/ && $password=~/^[\w\-\_]+$/;
         $days=~s/\D+//g;
         $days||=0;
         push(@arr, "<b>$login:$password:$days - ERROR:login already exist</b>"),next if $db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$login);
         my $passwd_hash = XUtils::GenPasswdHash($password);
         $db->Exec("INSERT INTO Users 
                    SET usr_login=?, 
                        usr_password=?, 
                        usr_email=?,
                        usr_created=NOW(), 
                        usr_premium_expire=NOW()+INTERVAL ? DAY",$login,$passwd_hash,$email||'',$days);
         push @arr, "$login:$password:$days";
      }
      $result = join "<br>", @arr;
   }
   $ses->PrintTemplate("admin_users_add.html",
                       'list'   => $list,
                       'result' => $result,
                      );
}

sub AdminApprove
{
   return $ses->message("Access denied") if !$ses->getUser->{usr_adm} && !($c->{m_d} && $ses->getUser->{usr_mod} && $c->{files_approve});

	if($ses->checkToken() && $f->{approve_selected})
	{
	   my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})}) if $f->{file_id};
	   $db->Exec("UPDATE Files SET file_awaiting_approve=0 WHERE file_id IN ($ids)") if $ids;
	   return $ses->redirect("$c->{site_url}/?op=moderator_approve");
	}
	if($ses->checkToken() && $f->{del_selected})
	{
	   my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{file_id})}) if $f->{file_id};
	   my $files = $db->SelectARef("SELECT * FROM Files WHERE file_id IN ($ids)") if $ids;
	   $ses->DeleteFilesMass($files) if $files;
	   return $ses->redirect("$c->{site_url}/?op=moderator_approve");
	}

   my $list = $db->SelectARef("SELECT f.*, u.*, s.srv_htdocs_url, INET_NTOA(file_ip) AS ip2
      FROM Files f
      LEFT JOIN Users u ON u.usr_id=f.usr_id
      LEFT JOIN Servers s ON s.srv_id=f.srv_id
      WHERE file_awaiting_approve
      ORDER BY file_created DESC");
   for(@$list)
   {
      $_->{download_link} = $ses->makeFileLink($_);

	   my $thumbs_dir = $_->{srv_htdocs_url};
	   $thumbs_dir=~s/^(.+)\/.+$/$1\/thumbs/;
      my $dx = sprintf("%05d",($_->{file_real_id}||$_->{file_id})/$c->{files_per_folder});
      if($_->{file_name} =~ /\.(avi|divx|xvid|mpg|mpeg|vob|mov|3gp|flv|mp4|wmv|mkv)$/i)
      {
		   for my $i (1..10)
	      {
	         push @{$_->{series}}, { url => "$thumbs_dir/$dx/$_->{file_real}_$i.jpg" };
	      }
      }

      $_->{file_size} = $ses->makeFileSize($_->{file_size});
   }
   return $ses->PrintTemplate("admin_approve.html",
      list => $list,
      token => $ses->genToken,
      );
}

sub AdminNews
{
   if($f->{del_id} && $ses->checkToken)
   {
      return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
      $db->Exec("DELETE FROM News WHERE news_id=?",$f->{del_id});
      $db->Exec("DELETE FROM Comments WHERE cmt_type=2 AND cmt_ext_id=?",$f->{del_id});
      return $ses->redirect('?op=admin_news');
   }
   my $news = $db->SelectARef("SELECT n.*, COUNT(c.cmt_id) as comments
                               FROM News n 
                               LEFT JOIN Comments c ON c.cmt_type=2 AND c.cmt_ext_id=n.news_id
                               GROUP BY n.news_id
                               ORDER BY created DESC".$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*) FROM News");
   for(@$news)
   {
      $_->{site_url} = $c->{site_url};
   }
   $ses->PrintTemplate("admin_news.html",
                       'news' => $news,
                       'paging' => $ses->makePagingLinks($f,$total),
                       'token'  => $ses->genToken,
                      );
}

sub AdminNewsEdit
{
   
   if($f->{save} && $ses->checkToken)
   {
      return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
      $f->{news_text} = $ses->{cgi_query}->param('news_text');
      $f->{news_title2}=lc $f->{news_title};
      $f->{news_title2}=~s/[^\w\s]//g;
      $f->{news_title2}=~s/\s+/-/g;
      if($f->{news_id})
      {
         $db->Exec("UPDATE News SET news_title=?, news_title2=?, news_text=?, created=? WHERE news_id=?",$f->{news_title},$f->{news_title2},$f->{news_text},$f->{created},$f->{news_id});
      }
      else
      {
         $db->Exec("INSERT INTO News SET news_title=?, news_title2=?, news_text=?, created=?",$f->{news_title},$f->{news_title2},$f->{news_text},$f->{created},$f->{news_id});
      }
      return $ses->redirect('?op=admin_news');
   }
   my $news = $db->SelectRow("SELECT * FROM News WHERE news_id=?",$f->{news_id});
   $news->{created} = $db->SelectOne("SELECT NOW()");
   $ses->PrintTemplate("admin_news_form.html",
                       %{$news},
                       'token'  => $ses->genToken,
                      );
}

sub AdminMassEmail
{
   if($f->{'send'} && $ENV{REQUEST_METHOD} eq 'POST' && $ses->checkToken)
   {
      return $ses->message("Not allowed in Demo mode") if $c->{demo_mode};
      return $ses->message("Subject required") unless $f->{subject};
      return $ses->message("Message") unless $f->{body};

      my $filter_utype = " AND usr_premium_expire > NOW()" if $f->{filter_utype} eq 'prem';
      $filter_utype = " AND usr_premium_expire <= NOW()" if $f->{filter_utype} eq 'free';
      my $filter_lastlogin = " AND usr_lastlogin > NOW() - INTERVAL $f->{filter_lastlogin} DAY"
         if $f->{filter_lastlogin};
      my $filter_users=" AND usr_id IN (".join(',',grep{/^\d+$/}@{ARef($f->{usr_id})}).")"
         if $f->{usr_id};
      my $filter_no_emails=" AND usr_no_emails=0" unless $filter_users;

      my $users = $db->SelectARef("SELECT usr_id,usr_login,usr_email 
                                   FROM Users 
                                   WHERE 1
                                   $filter_utype 
                                   $filter_lastlogin
                                   $filter_users
                                   $filter_no_emails");
      $|++;
      print"Content-type:text/html\n\n<HTML><BODY>";
      $c->{email_text}=1;
      my $cx;
      #die $#$users;
      for my $u (@$users)
      {
         next unless $u->{usr_email};
         my $body = $f->{body};
         $body=~s/%username%/$u->{usr_login}/egis;
         $body=~s/%unsubscribe_url%/"$c->{site_url}\/?op=unsubscribe&id=$u->{usr_id}&email=$u->{usr_email}"/egis;
         $ses->SendMail($u->{usr_email},$c->{email_from},$f->{subject},$body);
         print"Sent to $u->{usr_email}<br>\n";
         $cx++;
      }
      print"<b>DONE.</b><br><br>Sent to <b>$cx</b> users.<br><br><a href='?op=admin_users'>Back to User Management</a>";
      return;
   }
   my @users = map{{usr_id=>$_}} @{&ARef($f->{usr_id})};
   $ses->PrintTemplate("admin_mass_email.html",
                       users => \@users,
                       users_num => scalar @users,
                       token      => $ses->genToken(op => 'admin_mass_email'),
                       );
}

sub CheckFiles
{
   $f->{list}=~s/\r//gs;
   my ($i,@arr);
   for( split /\n/, $f->{list} )
   {
      $i++;
      my ($code,$fname) = /\w\/(\w{12})\/?(.*?)$/;
      next unless $code;
      $fname=~s/\.html?$//i;
      $fname=~s/_/ /g;
      #my $filter_fname="AND file_name='$fname'" if $fname=~/^[^'"<>]+$/;
      my $file = $db->SelectRow("SELECT f.file_id,f.file_name,f.file_size,s.srv_status FROM Files f, Servers s WHERE f.file_code=? AND s.srv_id=f.srv_id",$code);
      push(@arr,{url=>$_,color=>'red',   status=>"Not found!"}),next unless $file;
      $file->{file_name}=~s/_/ /g;
      push(@arr,{url=>$_,color=>'red',   status=>"Filename don't match!"}),next if $fname && $file->{file_name} ne $fname;
      push(@arr,{url=>$_,color=>'orange',status=>"Found. Server is not available at the moment"}),next if $file->{srv_status} eq 'OFF';
      $file->{fsize} = $ses->makeFileSize($file->{file_size});
      push(@arr,{url=>$_,color=>'green', status=>"Found", fsize=>$file->{fsize}});
   }
   $ses->PrintTemplate("checkfiles.html",
                       'list' => \@arr,
                      );
}

sub Catalogue
{
   return $ses->redirect($c->{site_url}) unless $c->{enable_catalogue};
   return $ses->message("Catalogue allowed for registered users only!") if $c->{catalogue_registered_only} && !$ses->getUser;
   $f->{page}||=1;
   $f->{per_page}=30;
   my $exts = {'vid' => 'avi|mpg|mpeg|mkv|wmv|mov|3gp|vob|asf|qt|m2v|divx|mp4|flv|rm',
               'aud' => 'mp3|wma|ogg|flac|wav|aac|m4a|mid|mpa|ra',
               'img' => 'jpg|jpeg|png|gif|bmp|eps|ps|psd|tif',
               'arc' => 'zip|rar|7z|gz|pkg|tar',
               'app' => 'exe|msi|app|com'
              }->{$f->{ftype}};
   my $filter_ext = "AND file_name REGEXP '\.($exts)\$' " if $exts;
   my $fsize_logic = $f->{fsize_logic} eq 'gt' ? '>' : '<';
   my $filter_size = "AND file_size $fsize_logic ".($f->{fsize}*1048576) if $f->{fsize};
   my $filter = "AND (file_name LIKE '%$f->{k}%' OR file_descr LIKE '%$f->{k}%')" if $f->{k}=~/^[^\"\'\;\\]{3,}$/;
   my $list = $db->SelectARef("SELECT f.*,
                                      TO_DAYS(CURDATE())-TO_DAYS(file_created) as created,
                                      s.srv_htdocs_url
                               FROM Files f, Servers s
                               WHERE file_public=1
                               AND f.srv_id=s.srv_id
                               $filter
                               $filter_ext
                               $filter_size
                               ORDER BY file_created DESC".$ses->makePagingSQLSuffix($f->{page}) );
   my $total = $db->SelectOne("SELECT COUNT(*)
                               FROM Files f
                               WHERE file_public=1
                               $filter
                               $filter_ext
                               $filter_size");
   my $paging = $ses->makePagingLinks($f,$total,'reverse');

   my $cx;
   for(@$list)
   {
      $_->{site_url} = $c->{site_url};
      utf8::decode($_->{file_descr});
      $_->{file_descr} = substr($_->{file_descr},0,48).'&#133;' if length($_->{file_descr})>48;
      utf8::encode($_->{file_descr});
      $_->{file_size}     = $ses->makeFileSize($_->{file_size});
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{file_name}=~s/_/ /g;
      my ($ext) = $_->{file_name}=~/\.(\w+)$/i;

      my $file_name = $_->{file_name};
      utf8::decode($file_name);
      $_->{file_name_txt} = shorten($file_name, 30);
      utf8::encode($_->{file_name_txt});

      $ext=lc $ext;
      $_->{img_preview} = $ext=~/^(ai|aiff|asf|avi|bmpbz2|css|doc|eps|gif|gz|html|jpg|jpeg|mid|mov|mp3|mpg|mpeg|ogg|pdf|png|ppt|ps|psd|qt|ra|ram|rm|rpm|rtf|tgz|tif|torrent|txt|wav|xls|xml|zip|exe|flv|swf|qma|wmv|mkv|rar)$/ ? "$c->{site_url}/images/icons/$ext-dist.png" : "$c->{site_url}/images/icons/default-dist.png";
      $_->{add_to_account}=1 if $ses->getUser && $_->{usr_id}!=$ses->getUserId;
      if( ($c->{m_i} && $_->{file_name}=~/\.(jpg|jpeg|gif|png|bmp)$/i )
          || ($c->{m_v} && $_->{file_name}=~/\.(avi|divx|flv|mp4|wmv|mkv)$/i) )
      {
         my $iurl = $_->{srv_htdocs_url};
         $iurl=~s/^(.+)\/.+$/$1\/i/;
         my $dx = sprintf("%05d",($_->{file_real_id}||$_->{file_id})/$c->{files_per_folder});
         $_->{img_preview2} = "$iurl/$dx/$_->{file_real}_t.jpg";
      }
      $_->{'tr'}=1 if ++$cx%3==0;
   }
   $ses->{header_extra} = qq{<link rel="alternate" type="application/rss+xml" title="$c->{site_name} new files" href="$c->{site_url}/catalogue.rss">};
   $ses->{page_title} = "$c->{site_name} File Catalogue: page $f->{page}";
   #die $f->{k};
   $ses->PrintTemplate("catalogue.html",
                       'files'  => $list,
                       'paging' => $paging,
                       'date'   => $f->{date},
                       'k'      => $f->{k},
                       'fsize'  => $f->{fsize},
                      );
}

sub RequestMoney
{
   return $ses->message("Money requests are restricted for Reseller users") if $ses->getUser->{usr_reseller};
   my $money = $ses->getUser->{usr_money};
   if($f->{convert_ext_acc})
   {
      return $ses->message("$ses->{lang}->{lang_need_at_least} \$$c->{convert_money}") if $money<$c->{convert_money};
      if($ses->getUser->{premium})
      {
         $db->Exec("UPDATE Users 
                    SET usr_money=usr_money-?, 
                        usr_premium_expire=usr_premium_expire+INTERVAL ? DAY 
                    WHERE usr_id=?",$c->{convert_money},$c->{convert_days},$ses->getUserId);
      }
      else
      {
         $db->Exec("UPDATE Users 
                    SET usr_money=usr_money-?, 
                        usr_premium_expire=NOW()+INTERVAL ? DAY 
                    WHERE usr_id=?",$c->{convert_money},$c->{convert_days},$ses->getUserId);
      }
      return $ses->redirect_msg("$c->{site_url}/?op=my_account","Your premium account extended for $c->{convert_days} days");
   }
   if($f->{convert_new_acc})
   {
      return $ses->message("You need at least \$$c->{convert_money}") if $money<$c->{convert_money};
      my $login = join '', map int rand 10, 1..7;
      while($db->SelectOne("SELECT usr_id FROM Users WHERE usr_login=?",$login)){ $login = join '', map int rand 10, 1..7; }
      my $password = $ses->randchar(10);
      my $passwd_hash = XUtils::GenPasswdHash($password);
      $db->Exec("INSERT INTO Users (usr_login,usr_password,usr_created,usr_premium_expire,usr_aff_id) VALUES (?,?,NOW(),NOW()+INTERVAL ? DAY,?)",$login,$passwd_hash,$c->{convert_days},$ses->getUserId);
      $db->Exec("UPDATE Users SET usr_money=usr_money-? WHERE usr_id=?",$c->{convert_money},$ses->getUserId);
      return $ses->message("$ses->{lang}->{lang_account_generated}<br>$ses->{lang}->{lang_login} / $ses->{lang}->{lang_password}:<br>$login<br>$password");
   }
   if($f->{convert_profit})
   {
      return $ses->message("You need at least \$$c->{min_payout}") if $money<$c->{min_payout};
      return $ses->message("Profit system is disabled") unless $c->{min_payout};
      return $ses->message("Enter Payment Info in you account settings") unless $ses->getUser->{usr_pay_email};

      my $exist_id = $db->SelectOne("SELECT id FROM Payments WHERE usr_id=? AND status='PENDING'",$ses->getUserId);
      if($c->{payout_policy} == 2 && $exist_id)
      {
         $db->Exec("UPDATE Payments SET amount=amount+? WHERE id=?",$money,$exist_id);
      }
      elsif($c->{payout_policy} == 1 || !$exist_id)
      {
         $db->Exec("INSERT INTO Payments SET
                        usr_id=?,
                        amount=?,
                        pay_email=?,
                        pay_type=?,
                        status='PENDING',
                        created=NOW()",
                        $ses->getUserId,
                        $money,
                        $ses->getUser->{usr_pay_email},
                        $ses->getUser->{usr_pay_type},
                        );
      }
      else
      {
         return $ses->message("You do already have a pending payout");
      }

      $db->Exec("UPDATE Users SET usr_money=0 WHERE usr_id=?",$ses->getUserId);
      return $ses->redirect_msg("$c->{site_url}/?op=request_money",$ses->{lang}->{lang_payout_requested});
   }

   my $pay_req = $db->SelectOne("SELECT SUM(amount) FROM Payments WHERE usr_id=? AND status='PENDING'",$ses->getUserId);

   my $convert_enough = 1 if $money >= $c->{convert_money};
   my $payout_enough = 1 if $money >= $c->{min_payout};
   $money = sprintf("%.02f",$money);

   my $payments = $db->SelectARef("SELECT *, DATE(created) as created2
                                   FROM Payments 
                                   WHERE usr_id=? 
                                   ORDER BY created DESC",$ses->getUserId);
   foreach(@$payments) {
      $_->{status} .= " ($_->{info})"
      if $_->{info};
   }

   $ses->PrintTemplate("request_money.html",
                       'usr_money'           => $money,
                       'convert_days'        => $c->{convert_days},
                       'convert_money'       => $c->{convert_money},
                       'payment_request'     => $pay_req,
                       'payout_enough'       => $payout_enough,
                       'convert_enough'      => $convert_enough,
                       'enabled_prem'        => $c->{enabled_prem},
                       'min_payout'          => $c->{min_payout},
                       'msg'                 => $f->{msg},
                       'payments'            => $payments,
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                       'token'      => $ses->genToken,
                      );
}

sub MyReseller
{
   return $ses->message("Not allowed") unless ($c->{m_k} && ($ses->getUser->{usr_reseller} || !$c->{m_k_manual}));
   my $user = $ses->getUser;

   my (@plans,$hh,$hr);
   for(split(/,/,$c->{m_k_plans}))
   {
      my ($price,$time) = /^(.+)=(.+)$/;
      $hh->{$price} = $time;
      $hr->{$time} = $price;
      my $time1=$time;

      $time=~s/h/ hours/i;
      $time=~s/d/ days/i;
      $time=~s/m/ months/i;
      
      push @plans, {price  => $price,
                    time   => $time,
                    time1  => $time1,
                    enough => $user->{usr_money}>=$price ? 1 : 0,
                   }
   }

   if($f->{del})
   {
      my $key = $db->SelectRow("SELECT * FROM PremiumKeys WHERE key_id=? AND usr_id=? AND usr_id_activated=0",$f->{del},$user->{usr_id});
      return $ses->message("Can't delete this key") unless $key;
      $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?",$hr->{$key->{key_time}},$user->{usr_id});
      $db->Exec("DELETE FROM PremiumKeys WHERE key_id=?",$key->{key_id});
      return $ses->redirect('?op=my_reseller');
   }

   if($f->{generate}=~/^[\d\.]+$/)
   {
      return $ses->message("You can have max 100 pending keys") if $db->SelectOne("SELECT COUNT(*) FROM PremiumKeys WHERE usr_id=? AND usr_id_activated=0",$user->{usr_id})>=100;
      my $time = $hh->{$f->{generate}};
      return $ses->message("Invalid price") unless $time;
      return $ses->message("Not enough money") if $ses->getUser->{usr_money} < $f->{generate};
      my @r = ('a'..'z');
      my $key_code = $r[rand scalar @r].$ses->randchar(13);
      $db->Exec("INSERT INTO PremiumKeys SET usr_id=?, key_code=?, key_time=?, key_price=?, key_created=NOW()",
                $user->{usr_id},$key_code,$time,$f->{generate});
      $db->Exec("UPDATE Users SET usr_money=usr_money-? WHERE usr_id=?",$f->{generate},$user->{usr_id});
      return $ses->redirect('?op=my_reseller');
   }

   my $keys = $db->SelectARef("SELECT *
                               FROM PremiumKeys 
                               WHERE usr_id=?
                               ORDER BY key_created DESC
                               ".$ses->makePagingSQLSuffix($f->{page}), $user->{usr_id} );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM PremiumKeys WHERE usr_id=?", $user->{usr_id});
   for(@$keys)
   {
      $_->{key_time}=~s/h/ hours/i;
      $_->{key_time}=~s/d/ days/i;
      $_->{key_time}=~s/m/ months/i;
   }

   $user->{usr_money} = sprintf("%.02f",$user->{usr_money});

   my @payment_types = grep { !$_->{reseller_disabled} } $ses->getPlugins('Payments')->get_payment_buy_with;

   $ses->PrintTemplate("my_reseller.html",
                       %$user,
                       'plans'  => \@plans,
                       'keys'   => $keys,
                       'paging' => $ses->makePagingLinks($f,$total),
                       'payment_types' => \@payment_types,
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                       %$c,
                      );
}

sub APIReseller
{
   $f->{login}=$f->{u};
   $f->{password}=$f->{p};
   &Login(no_redirect => 1);

   print"Content-type:text/html\n\n";
   print("ERROR:Reseller mod disabled"),return unless $c->{m_k};
   print("ERROR:Invalid username/password"),return unless $ses->getUser;
   print("ERROR:Not reseller user"),return if $c->{m_k_manual} && !$ses->getUser->{usr_reseller};
   print("ERROR:You can have max 100 pending keys"),return if $db->SelectOne("SELECT COUNT(*) FROM PremiumKeys WHERE usr_id=? AND usr_id_activated=0",$ses->getUserId)>=100;

   $f->{t}=lc $f->{t};
   my $price;
   for(split(/,/,$c->{m_k_plans}))
   {
      my ($pr,$time) = /^(.+)=(.+)$/;
      $price=$pr if $time eq $f->{t};
   }

   print("ERROR:Invalid time"),return unless $price;
   print("ERROR:Not enough money"),return if $ses->getUser->{usr_money} < $price;

   my @r = ('a'..'z');
   my $key_code = $r[rand scalar @r].$ses->randchar(13);
   $db->Exec("INSERT INTO PremiumKeys SET usr_id=?, key_code=?, key_time=?, key_price=?, key_created=NOW()",
             $ses->getUserId,$key_code,$f->{t},$price);
   my $id = $db->getLastInsertId;
   $db->Exec("UPDATE Users SET usr_money=usr_money-? WHERE usr_id=?",$price,$ses->getUserId);
   print"$id$key_code";
   return;
}

sub ReportFile
{
   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_code=?",$f->{id});
   return $ses->message("No such file") unless $file;
   my %secure = $ses->SecSave( 2, 5 );
   $f->{$_}=$ses->SecureStr($f->{$_}) for keys %$f;
   $f->{email}||=$ses->getUser->{usr_email} if $ses->getUser;
   $ses->PrintTemplate("report_file.html",
                       %{$f},
                       %secure,
                       'file_name' => $file->{file_name},
                       'ip'   => $ses->getIP(),
                      );
}

sub ReportFileSend
{
   return &ReportFile unless $ENV{REQUEST_METHOD} eq 'POST';
   return &ReportFile unless $ses->SecCheck( $f->{'rand'}, 2, $f->{code} );
   my $file = $db->SelectRow("SELECT * FROM Files WHERE file_code=?",$f->{id});
   return $ses->message("No such file") unless $file;

   $f->{msg}.="Email is not valid. " unless $f->{email} =~ /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
   $f->{msg}.="Name required. " unless $f->{name};
   $f->{msg}.="Message required. " unless $f->{message};
   
   return &ReportFile if $f->{msg};

   #$f->{message}="Reason: $f->{reason}\n\n$f->{message}";
   $f->{$_}=$ses->SecureStr($f->{$_}) for keys %$f;

   $db->Exec("INSERT INTO Reports SET file_id=?, usr_id=?, filename=?, name=?, email=?, reason=?, info=?, ip=INET_ATON(?), status='PENDING', created=NOW()",
             $file->{file_id}, $file->{usr_id}, $file->{file_name}, $f->{name}, $f->{email}, $f->{reason}, $f->{message}, $ses->getIP() );
   $f->{subject} = "$c->{site_name}: File reported";
   $f->{message} = "File was reported on $c->{site_name}.\n\nFilename: $file->{file_name}\n\nName: $f->{name}\nE-mail: $f->{email}\nReason: $f->{reason}\nIP: $ENV{REMOTE_ADDR}\n\n$f->{message}";
   $c->{email_text}=1;
   $ses->SendMail($c->{contact_email}, $c->{email_from}, $f->{subject}, $f->{message});
   return $ses->redirect("$c->{site_url}/?msg=Report sent successfully");
}

sub AdminReports
{
   return $ses->message("Access denied") if !$ses->getUser->{usr_adm} && !($c->{m_d} && $ses->getUser->{usr_mod} && $c->{m_d_a});
   my $ids = join(',',grep{/^\d+$/}@{&ARef($f->{id})}) if $f->{id};
   my $files = $db->SelectARef("SELECT r.id, f.* FROM Reports r
      LEFT JOIN Files f ON f.file_id=r.file_id
      WHERE id IN ($ids)
      AND f.file_id") if $ids;
   if($f->{view})
   {
      my $report = $db->SelectRow("SELECT *, INET_NTOA(ip) AS ip2 FROM Reports WHERE id=?", $f->{view});
      return $ses->PrintTemplate('admin_report_view.html', %$report);
   }
   if($f->{decline_selected} && $ses->checkToken)
   {
      $db->Exec("UPDATE Reports SET status='DECLINED' WHERE id IN ($ids)") if $ids;
      return $ses->redirect("$c->{site_url}/?op=admin_reports");
   }
   if($f->{del_selected} && $files && $ses->checkToken)
   {
      $db->Exec("UPDATE Reports SET status='APPROVED' WHERE id IN ($ids)") if $ids;
      $ses->DeleteFilesMass($files) if @$files;
      return $ses->redirect("$c->{site_url}/?op=admin_reports");
   }
   if($f->{ban_selected} && $files && $ses->checkToken)
   {
      for my $file (@$files)
      {
         $db->Exec("UPDATE Reports SET status='APPROVED', ban_size=?, ban_md5=?
            WHERE file_id=?",
            $file->{file_size},
            $file->{file_md5},
            $file->{file_id},
            );
      }
      $ses->DeleteFilesMass($files) if @$files;
      return $ses->redirect("$c->{site_url}/?op=admin_reports");
   }
   my $filter_status = $f->{history} ? "WHERE status<>'PENDING'" : "WHERE status='PENDING'";
   my $list = $db->SelectARef("SELECT r.*, f.*, INET_NTOA(ip) as ip,
                               (SELECT u.usr_login FROM Users u WHERE r.usr_id=u.usr_id) as usr_login
                               FROM Reports r 
                               LEFT JOIN Files f ON r.file_id = f.file_id
                               $filter_status
                               ORDER BY r.created DESC".$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*)
                               FROM Reports r
                               $filter_status");
   for(@$list)
   {
      $_->{site_url} = $c->{site_url};
      $_->{file_size2} = sprintf("%.02f Mb",$_->{file_size}/1048576);
      $_->{info} =~ s/\n/<br>/gs;
      $_->{"status_$_->{status}"}=1;
      $_->{status}.=', BANNED' if $_->{ban_size};
   }
   $ses->PrintTemplate("admin_reports.html",
                       'list'    => $list,
                       'paging'  => $ses->makePagingLinks($f,$total),
                       'history' => $f->{history},
                       'token'      => $ses->genToken,
                      );
}

sub AdminAntiHack
{
   my $gen_ip = $db->SelectARef("SELECT INET_NTOA(ip) as ip_txt, SUM(money) as money, COUNT(*) as downloads
                                 FROM IP2Files 
                                 WHERE created>NOW()-INTERVAL 48 HOUR
                                 GROUP BY ip
                                 ORDER BY money DESC
                                 LIMIT 20");

   my $gen_user = $db->SelectARef("SELECT u.usr_login, u.usr_id, SUM(money) as money, COUNT(*) as downloads
                                 FROM IP2Files i, Users u
                                 WHERE created>NOW()-INTERVAL 48 HOUR
                                 AND i.usr_id=u.usr_id
                                 GROUP BY i.usr_id
                                 ORDER BY money DESC
                                 LIMIT 20");

   my $rec_user = $db->SelectARef("SELECT u.usr_login, u.usr_id, SUM(money) as money, COUNT(*) as downloads
                                 FROM IP2Files i, Users u
                                 WHERE created>NOW()-INTERVAL 48 HOUR
                                 AND i.owner_id=u.usr_id
                                 GROUP BY i.owner_id
                                 ORDER BY money DESC
                                 LIMIT 20");

   $ses->PrintTemplate("admin_anti_hack.html",
                       'gen_ip'     => $gen_ip,
                       'gen_user'   => $gen_user,
                       'rec_user'   => $rec_user,
                       'currency_symbol' => ($c->{currency_symbol}||'$'),
                      );
}

sub APIGetLimits
{
   if($f->{login} && $f->{password})
   {
      &Login(no_redirect => 1);
      $f->{error}="auth_error" unless $ses->getUser;
   }
   elsif($f->{session_id})
   {
      $ses->{cookies}->{$ses->{auth_cook}} = $f->{session_id};
      XUtils::CheckAuth($ses);
   }
   my $utype = $ses->getUser ? ($ses->getUser->{premium} ? 'prem' : 'reg') : 'anon';
   $c->{$_}=$c->{"$_\_$utype"} for qw(max_upload_files max_upload_filesize download_countdown captcha ads bw_limit remote_url direct_links down_speed);

   my $type_filter = $utype eq 'prem' ? "AND srv_allow_premium=1" : "AND srv_allow_regular=1";
   my $server = $db->SelectRow("SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max
                                $type_filter
                                ORDER BY srv_last_upload 
                                LIMIT 1",$c->{max_upload_filesize}||100);
   my $ext_allowed     = join '|', map{uc($_)." Files|*.$_"} split(/\|/,$c->{ext_allowed});
   my $ext_not_allowed = join '|', map{uc($_)." Files|*.$_"} split(/\|/,$c->{ext_not_allowed});
   my $login_logic = 1 if !$c->{enabled_anon} && ($c->{enabled_reg} || $c->{enabled_prem});
   $login_logic = 2 if $c->{enabled_anon} && !$c->{enabled_reg} && !$c->{enabled_prem};
   print "Set-Cookie: xfss=".$ses->{cookies_send}->{$ses->{auth_cook}}."\n";
   print"Content-type:text/xml\n\n";
   print"<Data>\n";
   print"<ExtAllowed>$ext_allowed</ExtAllowed>\n";
   print"<ExtNotAllowed>$ext_not_allowed</ExtNotAllowed>\n";
   print"<MaxUploadFilesize>$c->{max_upload_filesize}</MaxUploadFilesize>\n";
   print"<ServerURL>$server->{srv_cgi_url}</ServerURL>\n";
   print"<SessionID>".$ses->{cookies_send}->{$ses->{auth_cook}}."</SessionID>\n";
   print"<Error>$f->{error}</Error>\n";
   print"<SiteName>$c->{site_name}</SiteName>\n";
   print"<LoginLogic>$login_logic</LoginLogic>\n";
   print"</Data>";
   return;
}

sub CommentAdd
{
   XUtils::CheckAuth($ses);
   return $ses->message("File comments are not allowed") if $f->{cmt_type}==1 && !$c->{enable_file_comments};
   print(qq{Content-type:text/html\n\n\$\$('cnew').innerHTML+="<b class='err'>Comments enabled for registered users only!</b><br><br>"}),return
      if $c->{comments_registered_only} && !$ses->getUser;
   die("Invalid object ID") unless $f->{cmt_ext_id}=~/^\d+$/;
   if($ses->getUser)
   {
      $f->{cmt_name} = $ses->getUser->{usr_login};
      $f->{cmt_email} = $ses->getUser->{usr_email};
   }
   $f->{usr_id} = $ses->getUser ? $ses->getUserId : 0;
   $f->{cmt_name}=~s/(http:\/\/|www\.|\.com|\.net)//gis;
   $f->{cmt_name}    = $ses->SecureStr($f->{cmt_name});
   $f->{cmt_email}   = $ses->SecureStr($f->{cmt_email});
   $f->{cmt_text}    = $ses->SecureStr($f->{cmt_text});
   $f->{cmt_text} =~ s/(\_n\_|\n)/<br>/g;
   $f->{cmt_text} =~ s/\r//g;
   $f->{cmt_text} = substr($f->{cmt_text},0,800);
   $f->{cmt_name} ||= 'Anonymous';

   local *error = sub {
      print(qq{Content-type:text/html\n\n<b class='err'>$_[0]</b>}),return if $f->{cmt_type} == 1;
      return $ses->message($_[0]);
   };

   return &error("E-mail is not valid") if $f->{cmt_email} && $f->{cmt_email}!~/^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
   return &error("Too short comment text") if length($f->{cmt_text})<5;

   my $txt=$f->{cmt_text};
   $txt=~s/[\s._-]+//gs;
   return &error("Comment text contain restricted word") if $c->{bad_comment_words} && $txt=~/$c->{bad_comment_words}/i;

   $db->Exec("INSERT INTO Comments
              SET usr_id=?,
                  cmt_type=?,
                  cmt_ext_id=?,
                  cmt_ip=INET_ATON(?),
                  cmt_name=?,
                  cmt_email=?,
                  cmt_text=?
             ",$f->{usr_id},$f->{cmt_type},$f->{cmt_ext_id},$ses->getIP,$f->{cmt_name},$f->{cmt_email}||'',$f->{cmt_text});
   my $comment = $db->SelectRow("SELECT *, INET_NTOA(cmt_ip) as ip, DATE_FORMAT(created,'%M %e, %Y') as date, DATE_FORMAT(created,'%r') as time
                  FROM Comments
                  WHERE cmt_id=?",
                  $db->getLastInsertId);
   my $news = $db->SelectRow("SELECT * FROM News WHERE news_id=?", $f->{cmt_ext_id});
   $ses->setCookie('cmt_name',$f->{cmt_name});
   $ses->setCookie('cmt_email',$f->{cmt_email});
   return $f->{cmt_type} == 1
      ? $ses->PrintTemplate2("comment.html", %$comment)
      : $ses->redirect($ENV{HTTP_REFERER});
}

sub CommentDel
{
   return $ses->message("Access denied") unless $ses->getUser && $ses->getUser->{usr_adm};
   $db->Exec("DELETE FROM Comments WHERE cmt_id=?",$f->{cmt_id});
   return $ses->redirect($ENV{HTTP_REFERER});
}

sub CommentRedirect
{
   my ($cmt_type,$cmt_ext_id) = @_;
   if($cmt_type==1) # Files
   {
      my $file = $db->SelectRow("SELECT * FROM Files WHERE file_id=?",$cmt_ext_id);
      return $ses->message("Object doesn't exist") unless $file;
      $ses->setCookie("skip$file->{file_id}",1);
      return $ses->makeFileLink($file).'#comments';
   }
   elsif($cmt_type==2) # News
   {
      my $news = $db->SelectRow("SELECT * FROM News WHERE news_id=?",$cmt_ext_id);
      return $ses->message("Object doesn't exist") unless $news;
      return "$c->{site_url}/n$news->{news_id}-$news->{news_title2}.html#comments";
   }
   return $ses->message("Invalid object type");
}

sub Links
{
   my @links;
   for(split(/~/,$c->{external_links}))
   {
      my ($url,$name)=split(/\|/,$_);
      $name||=$url;
      $url="http://$url" unless $url=~/^https?:\/\//i;
      push @links, {url=>$url,name=>$name};
   }
   $ses->PrintTemplate('links.html',links => \@links);
}

sub AdminIPNLogs
{
   my $filter = "WHERE info LIKE '%$f->{key}%'" if $f->{key};
   my $list = $db->SelectARef("SELECT * FROM IPNLogs $filter ORDER BY ipn_id DESC".$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*) FROM IPNLogs $filter");
   for(@$list)
   {
      $_->{info}=~s/\n/<br>/g;
   }
   $ses->PrintTemplate('admin_ipn_logs.html',
                       list      => $list,
                       paging    => $ses->makePagingLinks($f,$total),
                       key       => $f->{key},
                      );
}

sub AdminBansList {
   require List::Util;
   $f->{per_page} = 50;

   if($ses->checkToken() && $f->{unban_all})
   {
      $db->Exec("UPDATE Users SET usr_status = 'OK' WHERE usr_id IN (SELECT usr_id FROM Bans)");
      $db->Exec("DELETE FROM Bans");
      return $ses->redirect("$c->{site_url}/?op=admin_bans_list");
   }
   elsif($ses->checkToken() && $f->{unban_user})
   {
      $db->Exec("UPDATE Users SET usr_status='OK' WHERE usr_id=?", $f->{unban_user});
      $db->Exec("DELETE FROM Bans WHERE usr_id=?", $f->{unban_user});
      $db->Exec("DELETE FROM LoginProtect WHERE usr_id=?", $f->{unban_user});
      return $ses->redirect("$c->{site_url}/?op=admin_bans_list");
   }
   elsif($ses->checkToken() && $f->{unban_ip})
   {
      $db->Exec("DELETE FROM Bans WHERE ip=INET_ATON(?)", $f->{unban_ip});
      $db->Exec("DELETE FROM LoginProtect WHERE ip=INET_ATON(?)", $f->{unban_ip});
      return $ses->redirect("$c->{site_url}/?op=admin_bans_list");
   }

   my $filter_login = "AND u.usr_login LIKE '%$f->{key}%'" if $f->{key};
   my $filter_ip = "AND ip=INET_ATON('$f->{key}')" if $f->{key};
   my $list_users = $db->SelectARef("SELECT t.*, u.usr_login
                  FROM Bans t
                  LEFT JOIN Users u ON u.usr_id=t.usr_id
                  WHERE t.usr_id
                  $filter_login
                  ORDER BY created DESC".$ses->makePagingSQLSuffix($f->{page}));
   my $list_ips = $db->SelectARef("SELECT *, INET_NTOA(ip) AS ip
                  FROM Bans
                  WHERE ip
                  $filter_ip
                  ORDER BY created DESC
                  ".$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Bans WHERE ip");
   my $total = List::Util::max($db->SelectOne("SELECT COUNT(*) FROM Bans WHERE ip"),
            $db->SelectOne("SELECT COUNT(*) FROM Bans WHERE usr_id"));
   $ses->PrintTemplate('admin_bans_list.html',
               list_users => $list_users,
               list_ips => $list_ips,
               paging    => $ses->makePagingLinks($f,$total),
               key => $f->{key},
               token => $ses->genToken(),
            );
}

sub AdminSites {
   if($f->{delete}) {
      $db->Exec("DELETE FROM Websites WHERE domain=?", $f->{domain});
      return $ses->redirect("$c->{site_url}/?op=admin_sites");
   }
   my $list = $db->SelectARef("SELECT ws.*, u.usr_login
               FROM Websites ws
               LEFT JOIN Users u ON u.usr_id=ws.usr_id"
               .$ses->makePagingSQLSuffix($f->{page}));
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Websites");
   $ses->PrintTemplate('admin_sites.html',
               list => $list,
               paging    => $ses->makePagingLinks($f,$total),
            );
}

sub AdminExternal {
   my @d1 = $ses->getTime();
   $d1[2]='01';
   my @d2 = $ses->getTime();
   my $day1 = $f->{date1}=~/^\d\d\d\d-\d\d-\d\d$/ ? $f->{date1} : "$d1[0]-$d1[1]-$d1[2]";
   my $day2 = $f->{date2}=~/^\d\d\d\d-\d\d-\d\d$/ ? $f->{date2} : "$d2[0]-$d2[1]-$d2[2]";

   if($f->{set_perm} && $ses->checkToken())
   {
      my $key_id = $1 if $f->{set_perm} =~ s/_(\d+)$//;
      my $perm = $1 if $f->{set_perm} =~ /^(perm_.*)/;
      $db->Exec("UPDATE APIKeys SET $perm=? WHERE key_id=?",
         $f->{value},
         $key_id);
      print "Content-type: application/json\n\n";
      print JSON::encode_json({ status => 'OK' });
      return;
   }
   if($f->{generate_key} && $ses->checkToken())
   {
      return $ses->message("Domain not specified") if !$f->{domain};
      my @r = ('a'..'z');
      my $key_code = $r[rand scalar @r].$ses->randchar(15);
      $db->Exec("INSERT INTO APIKeys SET domain=?, key_code=?", $f->{domain}, $key_code);
      return $ses->redirect("$c->{site_url}/?op=admin_external");
   }
   if($f->{del_key} && $ses->checkToken())
   {
      $db->Exec("DELETE FROM APIKeys WHERE key_id=?", $f->{del_key});
      return $ses->redirect("$c->{site_url}/?op=admin_external");
   }
   if($f->{stats})
   {
      my $key = $db->SelectRow("SELECT * FROM APIKeys WHERE key_id=?", $f->{stats});
      my $list = $db->SelectARef("SELECT * FROM APIStats WHERE key_id=?
         AND day>=?
         AND day<=?
         ORDER BY day",
         $f->{stats}, $day1, $day2);

      my $max_value = max( map { ($_->{bandwidth_in}, $_->{bandwidth_out}) } @$list );
      my ($divider, $unit_name) = $max_value > 2**30 ? (2**30, 'Gb') : (2**20, 'Mb');

      for my $row(@$list)
      {
         $row->{bandwidth_total} = $row->{bandwidth_in} + $row->{bandwidth_out};
         for(qw(bandwidth_in bandwidth_out bandwidth_total))
         {
            $row->{$_.'2'} = $ses->makeFileSize($row->{$_});
            $row->{$_} = sprintf("%0.4f", $row->{$_} / $divider);
         }
      }

      return $ses->PrintTemplate("admin_external_stats.html",
         %$key,
         list => $list,
         date1 => $day1,
         date2 => $day2,
         data => JSON::encode_json($list),
         unit_name => $unit_name);
   }

   my $list = $db->SelectARef("SELECT * FROM APIKeys");
   for(@$list)
   {
      $_->{requests_last_month} = $db->SelectOne("SELECT SUM(downloads + uploads) FROM APIStats
         WHERE key_id=?
         AND day > NOW() - INTERVAL 30 DAY",
         $_->{key_id});
      $_->{requests_last_month} ||= 0;
   }

   $ses->PrintTemplate('admin_external.html',
               list => $list,
               token => $ses->genToken);
}

sub update_api_stats
{
   my ($key, %opts) = @_;

   my @params = map { $opts{"inc_$_"} || 0 } qw(uploads downloads bandwidth_in bandwidth_out);

   $db->Exec("INSERT INTO APIStats SET key_id=?, day=CURDATE(),
      uploads=?, downloads=?, bandwidth_in=?, bandwidth_out=?
      ON DUPLICATE KEY UPDATE uploads=uploads+?, downloads=downloads+?, bandwidth_in=bandwidth_in+?, bandwidth_out=bandwidth_out+?",
      $key->{key_id},
      @params,
      @params);
}

sub External
{
   my ($key_id,$key_code) = $f->{api_key}=~/^(\d+)(\w+)$/;
   my $key = $db->SelectRow("SELECT * FROM APIKeys WHERE key_id=? AND key_code=?", $key_id, $key_code);
   return &SendJSON({ err => "Unauthorized" }) if !$key;
   return &SendJSON({ err => "No action" }) if !$f->{download} && !$f->{upload};

   for(qw(download upload))
   {
      return &SendJSON({ err => "Access denied: '$_'" }) if $f->{$_} && !$key->{"perm_$_"};
   }

   if($f->{download})
   {
      update_api_stats($key, inc_downloads => 1);

      my $file = $db->SelectRow("SELECT f.*, s.* FROM Files f
            LEFT JOIN Servers s ON s.srv_id=f.srv_id 
            WHERE file_code=?",
            $f->{file_code});
      return &SendJSON({ err => "No such file" }) if !$file;

      update_api_stats($key, inc_bandwidth_out => $file->{file_size});

      return &SendJSON({ direct_link => $ses->getPlugins('CDN')->genDirectLink($file) });
   }
   elsif($f->{upload})
   {
      my $user = XUtils::CheckLoginPass($ses,$f->{login}, $f->{password});
      return &SendJSON({ err => "Invalid login/pass" }) if $f->{login} && !$user;

      # Need to create a new session even for anonymous user in
      # order to register the stats after the file will be uploaded
      my $sess_id = &GetSession($user ? $user->{usr_id} : 0);
      die("No session") if !$sess_id;
      $db->Exec("UPDATE Sessions SET api_key_id=? WHERE session_id=?", $key->{key_id}, $sess_id);
      my $server = XUtils::SelectServer($ses, $user);
      my $utype = $user && $user->{utype} ? $user->{utype} : 'anon';

      return &SendJSON({
         upload_url => "$server->{srv_cgi_url}/upload.cgi?utype=$utype",
         sess_id => $sess_id,
      });
   }
   else
   {
      return &SendJSON({ err => "No action" });
   }
}

sub AddToReports
{
   my ($file) = @_;
   $db->Exec("INSERT INTO Reports SET file_id=?, usr_id=?, filename=?, name=?, email=?, reason=?, info=?, ip=INET_ATON(?), status='PENDING', created=NOW()",
      $file->{file_id},
      $ses->getUserId,
      $file->{file_name},
      $ses->getUser->{usr_login},
      $ses->getUser->{usr_email},
      'Mass DMCA',
      '',
      $ses->getIP);
}

sub MassDMCA
{
   return $ses->message("Access denied") if !($c->{m_d} && $ses->getUser->{usr_dmca_agent});
   if($f->{urls})
   {
      my @urls = split(/\n\r?/, $f->{urls});
      for(@urls)
      {
         my $file_code = $1 if $_ =~ /\/(\w{12})/;
         next if !$file_code;
         my $file = $db->SelectRow("SELECT * FROM Files WHERE file_code=?", $file_code);
         next if !$file;
         &AddToReports($file);
      }
      my $text = "Your report was accepted.";
      $text .= "<br>The files will be completely removed in $c->{dmca_expire} hours, or after manual approve."
         if $c->{dmca_expire};
      return $ses->redirect_msg("$c->{site_url}/?op=mass_dmca", $text)
   }

   return $ses->message("Not allowed") if !$ses->getUser->{usr_dmca_agent};
   return $ses->PrintTemplate('mass_dmca.html', dmca_hours => $c->{dmca_hours});
}

sub MakeMoney
{
   my @sizes = map{{t1=>$_}} split(/\|/,$c->{tier_sizes});
   $sizes[$_]->{t2}=$sizes[$_+1]->{t1} for(0..$#sizes-1);
   $sizes[$#sizes]->{t2}='*';

   my @tier1 = map{{amount=>$_}} split(/\|/,$c->{tier1_money});
   my @tier2 = map{{amount=>$_}} split(/\|/,$c->{tier2_money});
   my @tier3 = map{{amount=>$_}} split(/\|/,$c->{tier3_money});
   my @tier4 = map{{amount=>$_}} split(/\|/,$c->{tier4_money});

   require XCountries;

   my @countries1 = grep{$_} map{$XCountries::iso_to_country->{uc $_}} split(/\|/,$c->{tier1_countries});
   my @countries2 = grep{$_} map{$XCountries::iso_to_country->{uc $_}} split(/\|/,$c->{tier2_countries});
   my @countries3 = grep{$_} map{$XCountries::iso_to_country->{uc $_}} split(/\|/,$c->{tier3_countries});
   my @countries4 = grep{$_} map{$XCountries::iso_to_country->{uc $_}} split(/\|/,$c->{tier4_countries});

   $ses->PrintTemplate("make_money.html",
                       sizes => \@sizes,
                       tier1 => \@tier1,
                       tier2 => \@tier2,
                       tier3 => \@tier3,
                       tier4 => \@tier4,
                       countries1 => join(', ',@countries1),
                       countries2 => join(', ',@countries2),
                       countries3 => join(', ',@countries3),
                       countries4 => join(', ',@countries4),
                       tier_views_number => $c->{tier_views_number},
                      );
}

###
sub ARef
{
  my $data=shift;
  $data=[] unless $data;
  $data=[$data] unless ref($data) eq 'ARRAY';
  return $data;
}

sub getTime
{
    my ($t) = @_;
    my @t = $t ? localtime($t) : localtime();
    return ( sprintf("%04d",$t[5]+1900),
             sprintf("%02d",$t[4]+1), 
             sprintf("%02d",$t[3]), 
             sprintf("%02d",$t[2]), 
             sprintf("%02d",$t[1]), 
             sprintf("%02d",$t[0]) 
           );
}

sub makeSortSQLcode
{
  my ($f,$default_field) = @_;
  
  my $sort_field = $f->{sort_field} || $default_field;
  my $sort_order = $f->{sort_order} eq 'down' ? 'DESC' : '';
  $sort_field=~s/[^\w\_]+//g;

  return " ORDER BY $sort_field $sort_order ";
}

sub makeSortHash
{
   my ($f,$fields) = @_;
   my @par;
   foreach my $key (keys %{$f})
   {
    next if $key=~/^(sort_field|sort_order|load)$/i;
    my $val = $f->{$key};
    $key =~ s/['"]//g;
    $val =~ s/['"]//g;
    push @par, (ref($val) eq 'ARRAY' ? map({"$key=$_"}@$val) : "$key=$val");
   }
   my $params = join('&amp;',@par);
   my $sort_field = $f->{sort_field};
   my $sort_order = $f->{sort_order};
   $sort_field ||= $fields->[0];
   my $sort_order2 = $sort_order eq 'down' ? 'up' : 'down';   
   my %hash = ('sort_'.$sort_field         => 1,
               'sort_order_'.$sort_order2  => 1,
               'params'                    => $params,
              );
   for my $fld (@$fields)
   {
      if($fld eq $sort_field)
      {
         $hash{"s_$fld"}  = "<a href='?$params&amp;sort_field=$fld&amp;sort_order=$sort_order2'>";
         $hash{"s2_$fld"} = "<img border=0 src='$c->{site_url}/images/$sort_order.gif'>"
      }
      else
      {
         $hash{"s_$fld"}  = "<a href='?$params&amp;sort_field=$fld&amp;sort_order=down'>";
      }
      $hash{"s2_$fld"}.= "</a>";
   }

   return %hash;
}

sub EmailUnsubscribe
{
   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=? AND usr_email=?",$f->{id},$f->{email});
   return $ses->message("Invalid unsubsription link") unless $user;
   $db->Exec("UPDATE Users SET usr_no_emails=1 WHERE usr_id=?",$user->{usr_id});
   return $ses->message("You've successfully unsubribed from email newsleters.");
}

sub SendJSON
{
   print "Content-type:application/json\n\n", JSON::encode_json($_[0]);
}

1;
