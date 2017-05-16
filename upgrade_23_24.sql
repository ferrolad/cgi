ALTER TABLE `BtTracker` ADD COLUMN file_id int(10) unsigned NOT NULL AFTER peer_id;
ALTER TABLE `BtTracker` ADD COLUMN usr_id mediumint(8) unsigned NOT NULL AFTER file_id;
ALTER TABLE `Files` ADD COLUMN file_awaiting_approve tinyint(1) NOT NULL DEFAULT '0';
ALTER TABLE `Files` ADD COLUMN file_upload_method varchar(16) NOT NULL;
ALTER TABLE `Files` ADD COLUMN file_size_encoded BIGINT(20) UNSIGNED NOT NULL DEFAULT 0 AFTER file_size;
ALTER TABLE `Stats` CHANGE COLUMN `paid` `received` decimal(9,4) NOT NULL DEFAULT '0.0000';
ALTER TABLE `Stats` ADD COLUMN paid_to_users decimal(9,4) NOT NULL DEFAULT '0.0000';
ALTER TABLE `Users` ADD COLUMN usr_premium_traffic bigint(20) NOT NULL DEFAULT 0;
ALTER TABLE `Users` ADD COLUMN usr_sales_percent smallint(3) NOT NULL DEFAULT '0';
ALTER TABLE `Users` ADD COLUMN usr_rebills_percent smallint(3) NOT NULL DEFAULT '0';
ALTER TABLE `Users` ADD COLUMN usr_m_x_percent smallint(3) NOT NULL DEFAULT '0';
ALTER TABLE `Torrents` CHANGE COLUMN files files text NOT NULL;
ALTER TABLE `Transactions` ADD COLUMN target varchar(16) NOT NULL DEFAULT '';
ALTER TABLE `Sessions` ADD COLUMN api_key_id MEDIUMINT(8) UNSIGNED NOT NULL DEFAULT 0;
ALTER TABLE `Folders` ADD COLUMN fld_trashed TINYINT(1) NOT NULL DEFAULT 0;

CREATE TABLE `APIStats` (
  `key_id` mediumint(8) unsigned NOT NULL,
  `day` date NOT NULL,
  `uploads` int(10) unsigned NOT NULL DEFAULT '0',
  `downloads` int(10) unsigned NOT NULL DEFAULT '0',
  `bandwidth_in` bigint(20) unsigned NOT NULL DEFAULT '0',
  `bandwidth_out` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`key_id`,`day`));

CREATE TABLE `PremiumPackages` (
  `usr_id` mediumint(8) unsigned DEFAULT NULL,
  `type` varchar(16) DEFAULT NULL,
  `quantity` mediumint(10) unsigned NOT NULL DEFAULT '0',
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  KEY `usr_id` (`usr_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
