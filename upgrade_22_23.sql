ALTER TABLE Files ADD COLUMN file_trashed timestamp NOT NULL DEFAULT '0000-00-00 00:00:00';
ALTER TABLE IP2Files ADD COLUMN finished tinyint(1) NOT NULL DEFAULT '0';
ALTER TABLE IP2Files ADD COLUMN status text;
ALTER TABLE Servers ADD COLUMN srv_ftp tinyint(1) NOT NULL DEFAULT '0';
ALTER TABLE Torrents ADD COLUMN name varchar(128) NOT NULL DEFAULT '';
ALTER TABLE Users ADD COLUMN usr_dmca_agent tinyint(1) NOT NULL DEFAULT '0';
ALTER TABLE Users ADD COLUMN usr_aff_enabled tinyint(1) NOT NULL DEFAULT '0';
ALTER TABLE Users ADD COLUMN usr_aff_max_dl_size mediumint(8) unsigned NOT NULL DEFAULT '0';
ALTER TABLE Users ADD COLUMN usr_max_rs_leech mediumint(8) unsigned NOT NULL DEFAULT '0';
CREATE TABLE APIKeys (
  key_id mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  key_code varchar(16) NOT NULL,
  domain varchar(64) NOT NULL,
  perm_download tinyint(1) NOT NULL DEFAULT '0',
  perm_upload tinyint(1) NOT NULL DEFAULT '0',
  created timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (key_id),
  UNIQUE KEY domain (domain),
  UNIQUE KEY key_code (key_code)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE BtTracker (
  sid varchar(100) NOT NULL,
  peer_id varchar(20) NOT NULL,
  ip bigint(20) unsigned NOT NULL,
  port smallint(5) unsigned NOT NULL,
  last_announce timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  bytes_left bigint(20) unsigned NOT NULL DEFAULT '0',
  UNIQUE KEY sid (sid,peer_id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
