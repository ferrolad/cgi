package XFileConfig;
use strict;
use lib 'Modules';
use lib 'Plugins';
use Exporter;
@XFileConfig::ISA    = qw(Exporter);
@XFileConfig::EXPORT = qw($c);
use vars qw( $c );

$c=
{
 license_key => '',

 # MySQL settings
 db_host => 'localhost',
 db_login => '',
 db_passwd => '',
 db_name => '',

 default_language => 'english',

 # Passwords crypting random salt. Set it up once when creating system
 pasword_salt => '',

 # Secret key to crypt Download requests
 dl_key => '',

 # Your site name that will appear in all templates
 site_name => 'XFileSharing',

 # Your site URL, without trailing /
 site_url => '',

 # Your site cgi-bin URL, without trailing /
 site_cgi => '',

 # Path to your site htdocs folder
 site_path => '',

 cgi_path => '',

 # Delete Direct Download Links after X hours
 symlink_expire => '8', # hours

 # Do not expire premium user's files
 dont_expire_premium => '1',

 # Generated links format, 0-5
 link_format => '0',

 enable_catalogue => '1',

 # Allowed file extensions delimited with '|'
 # Leave blank to allow all extensions
 # Sample: 'jpg|gif',
 ext_allowed => '',

 # Not Allowed file extensions delimited with '|'
 # Leave it blank to disable this filter
 # Sample: 'exe|com'
 ext_not_allowed => '',

 # Banned IPs
 # Examples: '^(10.0.0.182)$' - ban 10.0.0.182, '^(10.0.1.125|10.0.0.\d+)$' - ban 10.0.1.125 & 10.0.0.*
 # Use \d+ for wildcard *
 ip_not_allowed => '^(10.0.0.182)$',

 # Banned filename parts
 fnames_not_allowed => '(warez|porno|crack|xfile|jump)',

 # Use captcha verification to avoid robots
 # 0 - disable captcha, 1 - image captcha (requires GD perl module installed), 2 - text captha, 3 - reCaptcha
 captcha_mode => '2',

 # Enable users to add descriptions to files
 enable_file_descr => '1',

 # Allow users to add comments to files
 enable_file_comments => '1',

 # Replace all chars except "a-zA-Z0-9.-" with underline
 sanitize_filename => '',

 # Enable page with Premium/Free download choice
 pre_download_page => '1',

 # Used for BW limit
 bw_limit_days => '3',

 charset => 'UTF-8',

 # Require e-mail registration
 registration_confirm_email => '1',

 # Mail servers not allowed for registration
 # Sample: 'mailinator.com|gmail.com'
 mailhosts_not_allowed => '(mailinator.com|yopmail.com)',

 # Reject comments with banned words
 bad_comment_words => '(fuck|shit)',

 # Add postfix to filename
 add_filename_postfix => '',

 # Don't show Download button when showing image
 image_mod_no_download => '',

 # Play mp3 files instantly
 mp3_mod => '',

 # Don't show Download button when showing mp3 player
 mp3_mod_no_download => '',

 # Don't show Download button when showing video player
 video_mod_no_download => '',

 # Keys used for reCaptcha
 recaptcha_pub_key => '',
 recaptcha_pri_key => '',

 m_i => '',
 m_v => '',
 m_r => '',
 
 mu_logins => '',
 nl_logins => '',
 ra_logins => '',

 ping_google_sitemaps => '',

 # Show last news in header for X days after addition
 show_last_news_days => '0',

 m_v_page => '0',

 # Check IP on download: exact, first3, first2, all
 link_ip_logic => 'exact',

#--- Anonymous users limits ---#

 # Enable anonymous upload
 enabled_anon => '1',

 # Max number of upload fields
 max_upload_files_anon => '2',

 # Maximum upload Filesize in Mbytes (0 to disable)
 max_upload_filesize_anon => '10',

 # Maximum number of downloads for single file (0 to disable)
 max_downloads_number_anon => '200',

 # Specify number of seconds users have to wait before download, 0 to disable
 download_countdown_anon => '5',

 # Captcha for downloads
 captcha_anon => '',

 # Show advertisement
 ads_anon => '1',

 # Limit Max bandwidth for IP per 'bw_limit_days' days
 bw_limit_anon => '5000',

 # Add download delay per 100 Mb file, seconds
 add_download_delay_anon => '0',

 # Allow remote URL uploads
 remote_url_anon => '',

 leech_anon => '',

 # Generate direct links
 direct_links_anon => '1',

 # Download speed limit, Kbytes/s
 down_speed_anon => '',

 # Maximum download size in Mbytes (0 to disable) 
 max_download_filesize_anon => '100',
#------#

#--- Registered users limits ---#

 # Enable user registration
 enabled_reg => '1',

 # Max number of upload fields
 max_upload_files_reg => '3',

 # Maximum disk space in Mbytes (0 to disable)
 disk_space_reg => '10000',

 # Maximum upload Filesize in Mbytes (0 to disable)
 max_upload_filesize_reg => '100',

 # Maximum number of downloads for single file (0 to disable)
 max_downloads_number_reg => '500',

 # Specify number of seconds users have to wait before download, 0 to disable
 download_countdown_reg => '3',

 # Captcha for downloads
 captcha_reg => '',

 # Show advertisement
 ads_reg => '1',

 # Limit Max bandwidth for IP per 'bw_limit_days' days
 bw_limit_reg => '10000',

 # Add download delay per 100 Mb file, seconds
 add_download_delay_reg => '0',

 # Allow remote URL uploads
 remote_url_reg => '1',

 leech_reg => '',

 # Generate direct links
 direct_links_reg => '1',

 # Download speed limit, Kbytes/s
 down_speed_reg => '',

 # Maximum download size in Mbytes (0 to disable) 
 max_download_filesize_reg => '500',

 max_rs_leech_reg => '200',

 torrent_dl_reg => '1',

#------#

#--- Premium users limits ---#

 # Enable premium accounts
 enabled_prem => '1',

 # Max number of upload fields
 max_upload_files_prem => '50',

 # Maximum disk space in Mbytes (0 to disable)
 disk_space_prem => '0',

 # Maximum upload Filesize in Mbytes (0 to disable)
 max_upload_filesize_prem => '0',

 # Maximum number of downloads for single file (0 to disable)
 max_downloads_number_prem => '0',

 # Specify number of seconds users have to wait before download, 0 to disable
 download_countdown_prem => '0',

 # Captcha for downloads
 captcha_prem => '',

 # Show advertisement
 ads_prem => '1',

 # Limit Max bandwidth for IP per 'bw_limit_days' days
 bw_limit_prem => '25000',

 # Add download delay per 100 Mb file, seconds
 add_download_delay_prem => '0',

 # Allow remote URL uploads
 remote_url_prem => '1',

 leech_prem => '',

 # Generate direct links
 direct_links_prem => '1',

 # Download speed limit, Kbytes/s
 down_speed_prem => '',

 # Maximum download size in Mbytes (0 to disable) 
 max_download_filesize_prem => '0',

 max_rs_leech_prem => '0',

 torrent_dl_prem => '1',

#------#

 # Logfile name
 admin_log => 'logs.txt',

 items_per_page => '20',

 # Files per dir, do not touch since server start
 files_per_folder => 5000,

 # Do not use, for demo site only
 demo_mode => 0,

##### Email settings #####

 # SMTP settings (optional)
 smtp_server   => '',
 smtp_user     => '',
 smtp_pass     => '',

 # This email will be in "From:" field in confirmation & contact emails
 email_from => '',

 # Subject for email notification
 email_subject      => "XFileSharing: new file(s) uploaded",

 # Email that Contact messages will be sent to
 contact_email => '',

 # Premium users payment plans
 # Example: 5.00=7,9.00=14,15.00=30 ($5.00 adds 7 premium days)
 payment_plans => '3.00=7,10.00=30,40.00=120,90=365',

 tier_sizes => '0|10|100',

 tier1_countries => 'US|CA',

 tier2_countries => 'DE|FR|GB',

 tier3_countries => 'RU|UA',

 ### Payment settings ###

 item_name => 'FileSharing+Service',
 currency_code => 'USD',

 paypal_email => '',
 paypal_url    => 'https://www.paypal.com/cgi-bin/webscr',
 #paypal_url	=> 'https://www.sandbox.paypal.com/cgi-bin/webscr',

 alertpay_email => '',

 # User registration coupons
 coupons => '',

 tla_xml_key => '',

 webmoney_merchant_id => '',
 webmoney_secret_key => '',

 smscoin_id => '',

 external_links => 'https://sibsoft.net|SibSoft~https://xfilesharing.com|XFilesharing Pro Demo~https://sibsoft.net/xfilesharing.html|File sharing script',

 # Language list to show on site
 languages_list => ['english','russian','german','french','arabic','turkish','polish','thai','spanish','japan','hungary','indonesia','dutch','hebrew'],

 show_server_stats => '1',

### NEW 1.7 ###

 # Start mp3 playing instantly
 mp3_mod_autoplay => '',

 # Match list between browser language code and language file
 # Full list could be found here: http://www.livio.net/main/charset.asp#language
 language_codes => {'en.*'             => 'english',
                    'cs'               => 'czech',
                    'da'               => 'danish',
                    'fr.*'             => 'french',
                    'de.*'             => 'german',
                    'p'                => 'polish',
                    'ru'               => 'russian',
                    'es.*'             => 'spanish',
                   },

 # Cut long filenames in MyFiles,AdminFiles
 display_max_filename => '40',

 # Delete records from IP2Files older than X days
 clean_ip2files_days => '14',

 paypal_subscription => '',

 domain => '',

 m_w => '',

 m_s => '',
 m_s_reg => '',

 anti_dupe_system => '',

 m_i_width => '200',
 m_i_height => '200',
 m_i_resize => '0',
 m_i_wm_position => '',
 m_i_wm_image => '',
 m_i_wm_padding => '',

 two_checkout_sid => '',

 torrent_dl_slots_reg => '3',
 torrent_dl_slots_prem => '3',

 plimus_contract_id => '',

 moneybookers_email => '',

 daopay_app_id => '',

 cashu_merchant_id => '',

 m_d => '',
 m_d_f => '',
 m_d_a => '',
 m_d_c => '',

 deurl_site => '',
 deurl_api_key => '',

 m_a => '',

 m_v_width => '600',
 m_v_height => '300',

 video_embed_anon => '',
 video_embed_reg => '1',
 video_embed_prem => '1',

### NEW 1.8 ###

 m_e => '',
 m_e_vid_width => '320',
 m_e_vid_quality => '24',
 m_e_audio_bitrate => '96',

 flash_upload_anon => '1',
 flash_upload_reg => '1',
 flash_upload_prem => '1',

 files_expire_access_anon => '5',
 files_expire_access_reg => '60',
 files_expire_access_prem => '0',

 # Add download delay after each file download, seconds
 file_dl_delay_anon => '90',
 file_dl_delay_reg => '60',
 file_dl_delay_prem => '0',

 m_n => '',

 max_money_last24 => '100',

 sale_aff_percent => '',

 referral_aff_percent => '5',

 min_payout => '50',

 del_money_file_del => '1',

 convert_money => '1',
 convert_days => '7',

 money_filesize_limit => '',

 dl_money_anon => '',
 dl_money_reg => '',
 dl_money_prem => '',

 tier1_money => '3|3|3',
 tier2_money => '2|2|3',
 tier3_money => '1|1|1',

 rs_logins => '',
 mf_logins => '',
 fs_logins => '',
 df_logins => '',
 ff_logins => '',
 es_logins => '',
 ug_logins => '',
 fe_logins => '',

 m_i_hotlink_orig => '',

 payout_systems => 'PayPal, Webmoney, Moneybookers, AlertPay, Plimus',

 mp3_mod_embed => '',

 mp3_embed_anon => '',
 mp3_embed_reg => '1',
 mp3_embed_prem => '1',

 m_b => '',
 rar_info_anon => '',
 rar_info_reg => '1',
 rar_info_prem => '1',


 twit_consumer1 => 'Ib9LtBjGpyKhrBKFgnJqag',
 twit_consumer2 => '3n8VdCQjgw4Qi9aMnxlzrm5KCw4Fsv6RlTlcIS5QO4g',

### NEW 1.9 ###

 m_e_flv => '',
 m_e_flv_bitrate => '450',

 show_more_files => '1',

 bad_ads_words => '(zoo|rape|suck)',

 tier4_countries => 'OTHERS',
 tier4_money => '1|1|1',

 cron_test_servers => '1',

 m_i_magick => '',

 m_k => '',
 m_k_plans => '0.5=2h,3=5d,10=30d,50=6m',
 m_k_manual => '1',

 deleted_files_reports => '1',

### NEW 2.0 ###
 image_mod_track_download => '1',

 m_x => '',
 m_x_rate => '10',
 m_x_prem => '1',

 m_y => '',
 m_y_ppd_dl => '100',
 m_y_ppd_sales => '0',
 m_y_pps_dl => '0',
 m_y_pps_sales => '50',
 m_y_mix_dl => '30',
 m_y_mix_sales => '30',
 m_y_default => 'PPS',
 m_y_interval_days => '5',

 no_money_from_uploader_ip => '1',
 no_money_from_uploader_user => '1',

 pre_download_page_alt => '1',

 m_g => '',

 m_p_premium_only => '1',

 admin_geoip => '1',

 upload_on_anon => '1',
 upload_on_reg => '1',
 upload_on_prem => '1',

 download_on_anon => '1',
 download_on_reg => '1',
 download_on_prem => '1',

 paypal_trial_days => '',

 happy_hours => '',

 no_anon_payments => '0',

 maintenance_upload => '', 
 maintenance_upload_msg => '', 
 maintenance_download => '', 
 maintenance_download_msg => '', 
 maintenance_full => '', 
 maintenance_full_msg => '',
 
 upload_disabled_countries => '', 
 download_disabled_countries => '', 

 torrent_autorestart => '1',

 comments_registered_only => '',
 catalogue_registered_only => '',
 okpay_receiver => '',
 okpay_url    => 'https://www.okpay.com/ipn-verify.html',

 hipay_url => 'https://payment.hipay.com/order/',
 #hipay_url => 'https://test-payment.hipay.com/order/',
 hipay_merchant_id => '',
 hipay_merchant_password => '',
 hipay_website_id => '',
 pwall_app_id => '',
 pwall_secret_key => '',
 posonline_operator_id => '',
 posonline_secret => '',

 #### NEW 2.0 ####
 bs_logins => '',
 wu_logins => '',
 show_direct_link => '',

 #### NEW 2.1 ####
 ss_logins => '',
 as_logins => '',
 ul_logins => '',

 m_a_code => '<table style="background:#f9f9f9;border:3px solid #c3c3c3;width:200px;height:160px;"><tr><td align=center>MY SAMPLE VIDEO ADS</td></tr></table>',
 mtgox_api_key => '',
 mtgox_secret => '',
 ikoruna_czk_rate => '',
 ikoruna_p_id => '',
 ikoruna_secret => '',
 pcash_site_id => '',
 sprypay_shop_id => '',
 perfectmoney_account => '',
 perfectmoney_secret => '',
 junglepay_campaign_id => '',
 click2sell_products => '',
 matomy_placement_id => '',
 matomy_secret => '',
 paylink_url => 'https://paylink.cc/process.htm',
 paylink_products => '',
 paylink_member => '',
 paylink_subscription => '',
 paylink_trial_days => '',
 authorize_login_id => '',
 authorize_secret => '',

 max_login_attempts_h => '',
 max_login_ips_h => '',

 # Social
 m_c => '',
 facebook_app_id => '',
 facebook_app_secret => '',
 google_app_id => '',
 google_app_secret => '',
 vk_app_id => '',
 vk_app_secret => '',

 # DeURL
 m_j => '',
 m_j_domain => '',
 m_j_instant => '',
 m_j_hide => '',

 # SolveMedia
 solvemedia_theme => 'White',
 solvemedia_size => '',
 solvemedia_challenge_key => '',
 solvemedia_verification_key => '',
 solvemedia_authentication_key => '',

 iframe_breaker => '',

 #### NEW 2.2 ####
 smtp_auth => '',

 firstdatapay_gateway_id => '',
 firstdatapay_password => '',
 firstdatapay_hmac_key => '',
 firstdatapay_key_id => '',

 downloadnolimit_site_id => '',
 downloadnolimit_secret => '',

 paysafecard_username => '',
 paysafecard_password => '',

 mobile_design => '1',
 docviewer => '1',
 docviewer_no_download => '',

 accept_x_forwarded_for => '',
 accept_cf_connecting_ip => '',

 lang_detection => '',
 ga_tracking_id => '',
 up_limit_days => '3',
 up_limit_anon => '',
 up_limit_reg => '',
 up_limit_prem => '',

 m_i_adult => '',
 sm_logins => '',
 m_y_ppd_rebills => '',
 m_y_pps_rebills => '',
 m_y_mix_rebills => '',

 m_v_player => 'jw6',

 m_n_100_complete => '',
 jw6_license => '',

 ### NEW 2.3 ####
 
 ext_not_expire => '',
 reg_enabled => '1',
 image_mod => '',
 m_n_100_complete_percent => '',
 ftp_upload => '',
 memcached_location => '',
 payout_policy => '',
 dmca_expire => '',
 trash_expire => '',
 external_keys => '',
 torrent_fallback_after_anon => '',
 torrent_fallback_after_reg => '',
 torrent_fallback_after_prem => '',
 show_splash_main => '1',
 m_y_manual_approve => '',
 m_y_embed_earnings => '',
 jw6_skin => '',
 enable_reports => '1',

 ### NEW 2.4 ####
 adfly_uid => '',
 currency_symbol => '$',
 file_public_default => '1',
 agree_tos_default => '1',
 mask_dl_link => '',
 files_approve => '',
 files_approve_regular_only => '',
 m_z => '',
 m_o => '',
 ftp_mod => '',
 ftp_mod_prem_only => '',
 m_e_preserve_orig => '',
 m_e_copy_when_possible => '',
 captcha_attempts_h => '3',
 traffic_plans => '1.75=1.74,2.15=2.07,3.37=3.49',
 m_n_upload_speed_anon => '',
 m_n_limit_conn_anon => '',
 m_n_dl_resume_anon => '',
 m_n_upload_speed_reg => '',
 m_n_limit_conn_reg => '',
 m_n_dl_resume_reg => '',
 m_n_upload_speed_prem => '',
 m_n_limit_conn_prem => '',
 m_n_dl_resume_prem => '',
 flowplayer_license => '',
 jw7_license => '',
 jw7_skin => '',
 ftp_upload_reg => '',
 ftp_upload_prem => '',

 # NEW 2.4.1
 no_adblock_earnings => '',
};

1;
