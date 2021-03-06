-- by pts@fazekas.hu at Thu Jan  4 18:58:01 CET 2007

-- Dat: MySQL 5.1 interprets length specifications in character column
--      definitions in characters. (Versions before MySQL 4.1 interpreted
--      them in bytes.) Lengths for BINARY and VARBINARY are in bytes.

SET NAMES 'utf8' COLLATE 'utf8_general_ci';
USE mysql;
CREATE DATABASE IF NOT EXISTS movemetafs;
DROP DATABASE movemetafs;
CREATE DATABASE movemetafs COLLATE 'utf8_general_ci';
USE movemetafs;
-- CREATE USER 'movemetafs_ro'@'localhost';
-- SET PASSWORD FOR 'movemetafs_ro'@'localhost' = OLD_PASSWORD('put_ro_password_here');  
-- GRANT Select ON movemetafs.* TO 'movemetafs_ro'@'localhost';
DELETE FROM mysql.user WHERE user='movemetafs_rw' AND host='localhost';
INSERT INTO mysql.user (user,host) VALUES ('movemetafs_rw','localhost');
FLUSH PRIVILEGES;
-- vvv SUXX: not reentrant because of this CREATE USER 
-- CREATE USER 'movemetafs_rw'@'localhost';
SET PASSWORD FOR 'movemetafs_rw'@'localhost' = PASSWORD('put_password_here');
GRANT Select,Insert,Update,Delete ON movemetafs.* TO 'movemetafs_rw'@'localhost';   
-- CREATE USER 'movemetafs_full'@'localhost';
-- SET PASSWORD FOR 'movemetafs_full'@'localhost' = PASSWORD('put_full_password_here');
-- GRANT ALL ON movemetafs.* TO 'movemetafs_full'@'localhost';

DROP TABLE IF EXISTS files;
-- Imp: what if sizeof(st_ino)>sizeof(INTEGER)?
-- Imp: later add sum_sha1 BINARY(40),
-- Dat: xprincipal doesn't start with slash, and it is not empty;
--      it is like .32/foo/bar/f.txt: filesystem .32, directory foo/bar,
--      file f.txt
-- Dat: descr is a free text description of the file (UTF-8)
-- Dat: we use VARBINARY because we don't want to convert filenames to UTF-8
-- Dat: fs can contain only ASCII (0..127) chars, except for `:'
-- Dat: it is good that the UNIQUE property of shortname is checked by MySQL
-- Dat: both Linux and MySQL have a limit of 255 in filenames (for shortname)
-- Dat: `ts' is last (re)insertion time. Please note that file gets removed
--      if it loses all its tags and descr.
-- Dat: `ts' is in GMT, it shouldn't be local time
-- SUXX: cannot add a UNIQUE index on a VARCHAR(256) column...
-- SUXX: `Specified key was too long; max key length is 767 bytes' (for UNIQUE indexes),
--       so we avoid UNIQUE indexes
CREATE TABLE files (
  xprincipal VARBINARY(32000) NOT NULL,
  shortname VARBINARY(255) NOT NULL UNIQUE,
  shortprincipal VARBINARY(255) NOT NULL,
  ino INTEGER UNSIGNED NOT NULL,
  fs VARBINARY(127) NOT NULL,
  ts TIMESTAMP NOT NULL DEFAULT NOW(),
  descr TEXT NOT NULL,
  INDEX(shortprincipal),
  INDEX(xprincipal(32000)),
  UNIQUE(ino,fs),
  INDEX(ts)
) ENGINE=InnoDB;

-- Dat: tagtxt: `q' or something else is appended to words separated by space,
--      see $mydb_concat_tags_sqlpart
DROP TABLE IF EXISTS taggings;
CREATE TABLE taggings (
  ino INTEGER UNSIGNED NOT NULL,
  fs VARBINARY(127) NOT NULL,
  tagtxt TEXT NOT NULL,
  FULLTEXT(tagtxt),
  UNIQUE(ino,fs)
) ENGINE=MyISAM;

-- Dat: each tag has a row here with ino==0 and fs==''
--      no matter if there are files associated to the tag or not
-- Dat: `ts' is last insertion time, not last retag time
-- Dat: `ts' is in GMT, it shouldn't be local time
DROP TABLE IF EXISTS tags;
CREATE TABLE tags (
  ino INTEGER UNSIGNED NOT NULL,
  fs VARBINARY(127) NOT NULL,
  tag VARCHAR(255),
  ts TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(tag,ino,fs),
  UNIQUE(ino,fs,tag),
  INDEX(ts)
) ENGINE=InnoDB;

-- Imp: what if sizeof(st_ino)>sizeof(INTEGER)?
-- Dat: mpoint starts by `/', doesn't contain `//', and it doesn't end with
   `//' except for `/'
-- Dat: mpoint is usually a valid mount point in /proc/mounts, except for
   `/'
-- Dat: stat(mpoint) yields (dev,root_ino)
-- Dat: stat(mpoint+"../../...") yields (dev,top_ino)
-- Dat: root_ino=mpoint_ino  except if mpoint='/'
-- Dat: fs is not empty
-- Dat: mpoint is UNIQUE (but keysize is too large for InnoDB)
-- Dat: fs='' is used for insertion
DROP TABLE IF EXISTS fss;
CREATE TABLE fss (
  id INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fs VARBINARY(127) NOT NULL UNIQUE,
  last_dev INTEGER UNSIGNED NOT NULL UNIQUE,
  uuid VARBINARY(127) NOT NULL,
  INDEX(uuid)
) ENGINE=InnoDB;
-- !!
--   root_ino INTEGER UNSIGNED NOT NULL,
--   top_ino INTEGER UNSIGNED NOT NULL,
--   CHECK(mpoint<>''),
--   INDEX(mpoint)
--   mpoint VARBINARY(32000) NOT NULL,
