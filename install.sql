/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `APIKeys`
--

CREATE TABLE `APIKeys` (
  `key_id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `key_code` varchar(16) NOT NULL,
  `domain` varchar(64) NOT NULL,
  `perm_download` tinyint(1) NOT NULL DEFAULT '0',
  `perm_upload` tinyint(1) NOT NULL DEFAULT '0',
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_used` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`key_id`),
  UNIQUE KEY `domain` (`domain`),
  UNIQUE KEY `key_code` (`key_code`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
--
-- Table structure for table `APIStats`
--

CREATE TABLE `APIStats` (
  `key_id` mediumint(8) unsigned NOT NULL,
  `day` date NOT NULL,
  `uploads` int(10) unsigned NOT NULL DEFAULT '0',
  `downloads` int(10) unsigned NOT NULL DEFAULT '0',
  `bandwidth_in` bigint(20) unsigned NOT NULL DEFAULT '0',
  `bandwidth_out` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`key_id`,`day`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Bans`
--

CREATE TABLE `Bans` (
  `usr_id` mediumint(8) unsigned NOT NULL,
  `ip` int(20) unsigned NOT NULL,
  `reason` varchar(32) DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `usr_id` (`usr_id`,`ip`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `BtTracker`
--

CREATE TABLE `BtTracker` (
  `sid` varchar(100) NOT NULL,
  `peer_id` varchar(20) NOT NULL,
  `file_id` int(10) unsigned NOT NULL,
  `usr_id` mediumint(8) unsigned NOT NULL,
  `ip` bigint(20) unsigned NOT NULL,
  `port` smallint(5) unsigned NOT NULL,
  `last_announce` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `bytes_left` bigint(20) unsigned NOT NULL DEFAULT '0',
  UNIQUE KEY `sid` (`sid`,`peer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
--
-- Table structure for table `Comments`
--

CREATE TABLE `Comments` (
  `cmt_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `cmt_type` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `cmt_ext_id` int(10) unsigned NOT NULL DEFAULT '0',
  `cmt_ip` int(10) unsigned NOT NULL DEFAULT '0',
  `cmt_name` varchar(32) NOT NULL DEFAULT '',
  `cmt_email` varchar(64) NOT NULL DEFAULT '',
  `cmt_website` varchar(100) NOT NULL DEFAULT '',
  `cmt_text` text NOT NULL,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`cmt_id`),
  KEY `ext` (`cmt_type`,`cmt_ext_id`),
  KEY `date` (`created`),
  KEY `user` (`usr_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `DelReasons`
--

CREATE TABLE `DelReasons` (
  `file_code` varchar(12) NOT NULL DEFAULT '',
  `file_name` varchar(100) NOT NULL DEFAULT '',
  `info` varchar(255) NOT NULL DEFAULT '',
  `last_access` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`file_code`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `Files`
--

CREATE TABLE `Files` (
  `file_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `srv_id` smallint(5) unsigned NOT NULL DEFAULT '0',
  `file_name` varchar(255) NOT NULL DEFAULT '',
  `file_descr` text NOT NULL,
  `file_public` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `file_code` varchar(12) NOT NULL DEFAULT '',
  `file_real` varchar(12) NOT NULL DEFAULT '',
  `file_real_id` int(10) unsigned NOT NULL DEFAULT '0',
  `file_del_id` varchar(10) NOT NULL DEFAULT '',
  `file_fld_id` int(11) NOT NULL DEFAULT '0',
  `file_downloads` int(10) unsigned NOT NULL DEFAULT '0',
  `file_views` int(10) unsigned NOT NULL DEFAULT '0',
  `file_size` bigint(20) unsigned NOT NULL DEFAULT '0',
  `file_size_encoded` bigint(20) unsigned NOT NULL DEFAULT '0',
  `file_password` varchar(32) NOT NULL DEFAULT '',
  `file_ip` int(20) unsigned NOT NULL DEFAULT '0',
  `file_md5` varchar(64) NOT NULL DEFAULT '',
  `file_spec` text NOT NULL,
  `file_last_download` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `file_created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `file_money` decimal(10,4) unsigned NOT NULL DEFAULT '0.0000',
  `file_premium_only` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `file_adult` tinyint(3) NOT NULL DEFAULT '0',
  `file_trashed` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `file_awaiting_approve` tinyint(1) NOT NULL DEFAULT '0',
  `file_upload_method` varchar(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`file_id`),
  KEY `real` (`file_real`),
  KEY `server` (`srv_id`),
  KEY `created` (`file_created`),
  KEY `code` (`file_code`),
  KEY `public` (`file_public`),
  KEY `user` (`usr_id`),
  KEY `folder` (`file_fld_id`),
  KEY `size` (`file_size`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `FilesDeleted`
--

CREATE TABLE `FilesDeleted` (
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `file_code` varchar(12) NOT NULL DEFAULT '',
  `file_real` varchar(100) NOT NULL DEFAULT '',
  `file_name` varchar(100) NOT NULL DEFAULT '',
  `deleted` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `hide` tinyint(3) unsigned NOT NULL DEFAULT '0',
  KEY `user` (`usr_id`,`deleted`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Folders`
--

CREATE TABLE `Folders` (
  `fld_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `fld_parent_id` int(10) unsigned NOT NULL DEFAULT '0',
  `fld_descr` text NOT NULL,
  `fld_name` varchar(128) NOT NULL DEFAULT '',
  `fld_trashed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`fld_id`),
  KEY `user` (`usr_id`,`fld_parent_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `IP2Files`
--

CREATE TABLE `IP2Files` (
  `file_id` int(10) unsigned NOT NULL DEFAULT '0',
  `ip` int(20) unsigned NOT NULL DEFAULT '0',
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `owner_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `size` bigint(20) unsigned NOT NULL DEFAULT '0',
  `money` decimal(8,4) unsigned NOT NULL DEFAULT '0.0000',
  `referer` varchar(255) NOT NULL DEFAULT '',
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `finished` tinyint(1) NOT NULL DEFAULT '0',
  `status` text,
  PRIMARY KEY (`file_id`,`ip`,`usr_id`),
  KEY `owner` (`owner_id`),
  KEY `user` (`usr_id`),
  KEY `ip` (`ip`,`created`),
  KEY `date` (`created`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
--
-- Table structure for table `IP2RS`
--

CREATE TABLE `IP2RS` (
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `size` bigint(20) unsigned NOT NULL DEFAULT '0',
  `ip` int(10) unsigned NOT NULL DEFAULT '0',
  KEY `created` (`created`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `IPNLogs`
--

CREATE TABLE `IPNLogs` (
  `ipn_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `info` text NOT NULL,
  PRIMARY KEY (`ipn_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `LoginProtect`
--

CREATE TABLE `LoginProtect` (
  `usr_id` mediumint(8) unsigned NOT NULL,
  `login` varchar(32) NOT NULL,
  `ip` int(20) unsigned NOT NULL,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `usr_id` (`usr_id`),
  KEY `ip` (`ip`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Misc`
--

CREATE TABLE `Misc` (
  `name` varchar(32) NOT NULL DEFAULT '',
  `value` varchar(255) NOT NULL DEFAULT '',
  `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `News`
--

CREATE TABLE `News` (
  `news_id` mediumint(9) unsigned NOT NULL AUTO_INCREMENT,
  `news_title` varchar(100) NOT NULL DEFAULT '',
  `news_title2` varchar(100) NOT NULL DEFAULT '',
  `news_text` text NOT NULL,
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`news_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `Payments`
--

CREATE TABLE `Payments` (
  `id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `amount` decimal(7,2) unsigned NOT NULL DEFAULT '0.00',
  `status` enum('PENDING','PAID','REJECTED') NOT NULL DEFAULT 'PENDING',
  `pay_email` varchar(64) NOT NULL DEFAULT '',
  `pay_type` varchar(16) NOT NULL DEFAULT '',
  `info` varchar(255) NOT NULL DEFAULT '',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`),
  KEY `user` (`usr_id`),
  KEY `stat` (`status`,`created`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `PaymentsLog`
--

CREATE TABLE `PaymentsLog` (
  `usr_id_from` mediumint(8) unsigned NOT NULL,
  `usr_id_to` mediumint(8) unsigned NOT NULL,
  `amount` decimal(9,5) DEFAULT NULL,
  `type` varchar(16) DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `PremiumKeys`
--

CREATE TABLE `PremiumKeys` (
  `key_id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `key_code` varchar(14) NOT NULL DEFAULT '',
  `key_time` varchar(8) NOT NULL DEFAULT '0',
  `key_price` decimal(10,2) unsigned NOT NULL DEFAULT '0.00',
  `key_created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `key_activated` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `usr_id_activated` mediumint(8) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`key_id`),
  KEY `user` (`usr_id`,`key_created`),
  KEY `created` (`key_created`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `PremiumPackages`
--

CREATE TABLE `PremiumPackages` (
  `usr_id` mediumint(8) unsigned DEFAULT NULL,
  `type` varchar(16) DEFAULT NULL,
  `quantity` mediumint(10) unsigned NOT NULL DEFAULT '0',
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  KEY `usr_id` (`usr_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `QueueTransfer`
--

CREATE TABLE `QueueTransfer` (
  `file_real` varchar(12) NOT NULL DEFAULT '',
  `file_id` int(10) unsigned NOT NULL DEFAULT '0',
  `srv_id1` smallint(5) unsigned NOT NULL DEFAULT '0',
  `srv_id2` smallint(5) unsigned NOT NULL DEFAULT '0',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `started` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `status` enum('PENDING','MOVING','ERROR') NOT NULL DEFAULT 'PENDING',
  `transferred` int(10) unsigned NOT NULL DEFAULT '0',
  `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `speed` smallint(5) unsigned NOT NULL DEFAULT '0',
  `copy` tinyint(3) unsigned DEFAULT NULL,
  `error` text NOT NULL,
  PRIMARY KEY (`file_real`),
  KEY `srv2` (`srv_id2`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Reports`
--

CREATE TABLE `Reports` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `file_id` int(10) unsigned NOT NULL DEFAULT '0',
  `usr_id` mediumint(8) unsigned DEFAULT '0',
  `filename` varchar(100) NOT NULL DEFAULT '',
  `name` varchar(64) NOT NULL DEFAULT '',
  `email` varchar(64) NOT NULL DEFAULT '',
  `reason` varchar(100) NOT NULL DEFAULT '',
  `info` text NOT NULL,
  `ip` int(20) unsigned NOT NULL DEFAULT '0',
  `status` enum('PENDING','APPROVED','DECLINED') NOT NULL DEFAULT 'PENDING',
  `ban_size` bigint(20) unsigned DEFAULT '0',
  `ban_md5` varchar(64) DEFAULT '',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`),
  KEY `status` (`status`),
  KEY `ban` (`ban_size`,`ban_md5`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `Servers`
--

CREATE TABLE `Servers` (
  `srv_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `srv_name` varchar(64) NOT NULL DEFAULT '',
  `srv_ip` varchar(16) NOT NULL DEFAULT '',
  `srv_cgi_url` varchar(255) NOT NULL DEFAULT '',
  `srv_htdocs_url` varchar(255) NOT NULL DEFAULT '',
  `srv_key` varchar(8) NOT NULL DEFAULT '',
  `srv_disk_max` bigint(20) unsigned NOT NULL DEFAULT '0',
  `srv_status` enum('ON','READONLY','OFF') NOT NULL DEFAULT 'ON',
  `srv_files` int(10) unsigned NOT NULL DEFAULT '0',
  `srv_disk` bigint(20) unsigned NOT NULL DEFAULT '0',
  `srv_allow_regular` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `srv_allow_premium` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `srv_torrent` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `srv_created` date NOT NULL DEFAULT '0000-00-00',
  `srv_last_upload` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `srv_countries` varchar(255) NOT NULL DEFAULT '',
  `srv_cdn` varchar(32) NOT NULL DEFAULT '',
  `srv_ftp` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`srv_id`),
  UNIQUE KEY `fs_key` (`srv_key`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Sessions`
--

CREATE TABLE `Sessions` (
  `session_id` char(16) NOT NULL DEFAULT '',
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `last_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `api_key_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`session_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `SrvData`
--

CREATE TABLE `SrvData` (
  `srv_id` smallint(5) unsigned NOT NULL DEFAULT '0',
  `name` varchar(24) NOT NULL DEFAULT '',
  `value` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`srv_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
--
-- Table structure for table `Stats`
--

CREATE TABLE `Stats` (
  `day` date NOT NULL DEFAULT '0000-00-00',
  `uploads` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `downloads` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `registered` smallint(5) unsigned NOT NULL DEFAULT '0',
  `bandwidth` bigint(20) unsigned NOT NULL DEFAULT '0',
  `received` decimal(9,4) NOT NULL DEFAULT '0.0000',
  `paid_to_users` decimal(9,4) NOT NULL DEFAULT '0.0000',
  PRIMARY KEY (`day`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Stats2`
--

CREATE TABLE `Stats2` (
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `day` date NOT NULL DEFAULT '0000-00-00',
  `downloads` int(10) unsigned NOT NULL DEFAULT '0',
  `sales` smallint(5) unsigned NOT NULL DEFAULT '0',
  `rebills` smallint(5) unsigned NOT NULL DEFAULT '0',
  `profit_dl` decimal(9,4) unsigned NOT NULL DEFAULT '0.0000',
  `profit_sales` decimal(9,4) unsigned NOT NULL DEFAULT '0.0000',
  `profit_rebills` decimal(9,4) unsigned NOT NULL DEFAULT '0.0000',
  `profit_refs` decimal(9,5) unsigned NOT NULL DEFAULT '0.00000',
  `profit_site` decimal(9,5) unsigned NOT NULL DEFAULT '0.00000',
  PRIMARY KEY (`usr_id`,`day`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Torrents`
--

CREATE TABLE `Torrents` (
  `sid` varchar(100) NOT NULL DEFAULT '',
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `srv_id` smallint(5) unsigned NOT NULL DEFAULT '0',
  `fld_id` int(11) unsigned NOT NULL DEFAULT '0',
  `name` varchar(128) NOT NULL DEFAULT '',
  `link_rcpt` varchar(64) NOT NULL DEFAULT '',
  `link_pass` varchar(32) NOT NULL DEFAULT '',
  `files` text NOT NULL,
  `progress` varchar(100) NOT NULL DEFAULT '',
  `status` enum('WORKING','DONE') NOT NULL DEFAULT 'WORKING',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  KEY `sid` (`sid`),
  KEY `user` (`usr_id`),
  KEY `status` (`status`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
--
-- Table structure for table `Transactions`
--

CREATE TABLE `Transactions` (
  `id` varchar(10) NOT NULL DEFAULT '',
  `usr_id` mediumint(9) unsigned NOT NULL DEFAULT '0',
  `amount` decimal(10,2) unsigned NOT NULL DEFAULT '0.00',
  `days` smallint(5) unsigned NOT NULL DEFAULT '0',
  `txn_id` varchar(100) NOT NULL DEFAULT '',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `aff_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `ip` int(20) unsigned NOT NULL DEFAULT '0',
  `plugin` varchar(16) NOT NULL DEFAULT '',
  `verified` tinyint(4) unsigned NOT NULL DEFAULT '0',
  `domain` varchar(32) NOT NULL DEFAULT '',
  `ref_url` varchar(255) NOT NULL DEFAULT '',
  `email` varchar(64) NOT NULL DEFAULT '',
  `rebill` tinyint(1) NOT NULL DEFAULT '0',
  `target` varchar(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `user` (`usr_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `UserData`
--

CREATE TABLE `UserData` (
  `usr_id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(24) NOT NULL DEFAULT '',
  `value` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`usr_id`,`name`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Users`
--

CREATE TABLE `Users` (
  `usr_id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `usr_login` varchar(32) NOT NULL DEFAULT '',
  `usr_password` varchar(100) NOT NULL DEFAULT '',
  `usr_email` varchar(64) NOT NULL DEFAULT '',
  `usr_adm` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `usr_mod` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `usr_status` enum('OK','PENDING','BANNED') NOT NULL DEFAULT 'OK',
  `usr_profit_mode` enum('PPD','PPS','MIX') NOT NULL DEFAULT 'PPD',
  `usr_premium_expire` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `usr_direct_downloads` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `usr_rapid_login` varchar(32) NOT NULL DEFAULT '',
  `usr_rapid_pass` varchar(32) NOT NULL DEFAULT '',
  `usr_aff_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `usr_created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `usr_lastlogin` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `usr_plan_changed` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `usr_lastip` int(20) unsigned NOT NULL DEFAULT '0',
  `usr_pay_email` varchar(64) NOT NULL DEFAULT '',
  `usr_pay_type` varchar(16) NOT NULL DEFAULT '',
  `usr_disk_space` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `usr_bw_limit` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `usr_up_limit` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `usr_max_rs_leech` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `usr_money` decimal(11,5) unsigned NOT NULL DEFAULT '0.00000',
  `usr_no_emails` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `usr_security_lock` varchar(8) NOT NULL DEFAULT '',
  `usr_reseller` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `usr_notes` text NOT NULL,
  `usr_profit_mode_changed` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `usr_social` varchar(16) NOT NULL DEFAULT '',
  `usr_social_id` varchar(32) NOT NULL DEFAULT '',
  `usr_aff_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `usr_aff_max_dl_size` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `usr_dmca_agent` tinyint(1) NOT NULL DEFAULT '0',
  `usr_sales_percent` smallint(3) NOT NULL DEFAULT '0',
  `usr_rebills_percent` smallint(3) NOT NULL DEFAULT '0',
  `usr_m_x_percent` smallint(3) NOT NULL DEFAULT '0',
  `usr_premium_traffic` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`usr_id`),
  KEY `login` (`usr_login`),
  KEY `aff_id` (`usr_aff_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
--
-- Table structure for table `Websites`
--

CREATE TABLE `Websites` (
  `usr_id` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `domain` varchar(64) NOT NULL DEFAULT '',
  `created` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`domain`),
  KEY `user` (`usr_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;