package XFSConfig;
use strict;
use lib 'Modules';
use Exporter ();
@XFSConfig::ISA    = qw(Exporter);
@XFSConfig::EXPORT = qw($c);
use vars qw( $c );

$c=
{
 # Directory for temporary using files, witout trailing /
 temp_dir => '',

 # Directory for uploaded files, witout trailing /
 upload_dir => '',

 cgi_dir => '',

 # Path to htdocs/files folder - to generate direct links, witout trailing /
 htdocs_dir => '',

 # Path to htdocs/tmp folder
 htdocs_tmp_dir => '',

 # FileServer auth key (generating when adding server)
 fs_key => '',

 dl_key => '',

 # FileServer status
 srv_status => 'READONLY',

 # Your Main site URL, witout trailing /
 site_url => '',

 # Your Main site cgi-bin URL, witout trailing /
 site_cgi => '',

 m_i => '1',
 m_v => '',
 m_r => '',
 
 mu_logins => '',
 nl_logins => '',

 m_i_resize => '0',

 bitflu_address => '127.0.0.1:4081',
# bitflu_address => '10.0.0.12:4081',


#--- Anonymous users limits ---#
 enabled_anon => '1',

 # Max number of upload fields
 max_upload_files_anon => '2',

 # Maximum upload Filesize in Mbytes (0 to disable)
 max_upload_filesize_anon => '10',

 # Allow remote URL uploads
 remote_url_anon => '1',

 leech_anon => '1',
#------#

#--- Registered users limits ---#
 enabled_reg => '1',

 # Max number of upload fields
 max_upload_files_reg => '3',

 # Maximum upload Filesize in Mbytes (0 to disable)
 max_upload_filesize_reg => '100',

 # Allow remote URL uploads
 remote_url_reg => '1',

 leech_reg => '1',
#------#

#--- Premium users limits ---#
 enabled_prem => '1',

 # Max number of upload fields
 max_upload_files_prem => '50',

 # Maximum upload Filesize in Mbytes (0 to disable)
 max_upload_filesize_prem => '0',

 # Allow remote URL uploads
 remote_url_prem => '1',

 leech_prem => '1',
#------#

 # Banned IPs
 # Use \d+ for wildcard *
 ip_not_allowed => '^(10.0.0.182)$',

 # Logfile name
 uploads_log => 'logs.txt',

 # Enable scanning file for viruses with ClamAV after upload (Experimental)
 # You need ClamAV installed on your server
 enable_clamav_virus_scan => '0',

 # Update progress bar using streaming method
 ajax_stream => 0,

 #Files per dir, do not touch since server start
 files_per_folder => 5000,

##### Custom error messages #####

 msg => { upload_size_big   => "Maximum total upload size exceeded<br>Max total upload size is: ",
          file_size_big     => "Max filesize limit exceeded! Filesize limit: ",
          no_temp_dir       => "No temp dir exist! Please fix your temp_dir variable in config.",
          no_target_dir     => "No target dir exist! Please fix your target_dir variable in config.",
          no_templates_dir  => "No Templates dir exist! Please fix your templates_dir variable in config.",
          transfer_complete => "Transfer complete!",
          transfer_failed   => "Upload failed!",
          null_filesize     => "have null filesize or wrong file path",
          bad_filename      => "is not acceptable filename! Skipped.",
          too_many_files    => "wasn't saved! Number of files limit exceeded.",
          saved_ok          => "saved successfully.",
          wrong_password    => "You've entered wrong password.<br>Authorization required.",
          ip_not_allowed    => "You are not allowed to upload files",
        },

 ### NEW 1.7 ###
 m_i_width => '',
 m_i_height => '',
 m_i_wm_position => '',
 m_i_wm_image => '',

 fs_files_url => '',
 fs_cgi_url => '',

 ### NEW 1.8 ###
 m_e => '',
 m_e_vid_width => '',
 m_e_vid_quality => '',
 m_e_audio_bitrate => '',

 rs_logins => '',
 mf_logins => '',
 fs_logins => '',
 df_logins => '',
 ff_logins => '',
 es_logins => '',
 ug_logins => '',
 fe_logins => '',

 m_i_hotlink_orig => '',

 m_b => '',

### NEW 1.9 ###

 m_e_flv => '',
 m_e_flv_bitrate => '',

 m_i_magick => '',

#### NEW 2.0 ####

 bs_logins => '',

#### NEW 2.1 ####

 ss_logins => '',
 as_logins => '',
 ul_logins => '',

#### NEW 2.2 ####
 ra_logins => '',


};

1;
