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
-- Dat: principal doesn't start with slash, and it is not empty
-- Dat: descr is a free text description of the file (UTF-8)
-- Dat: we use VARBINARY because we don't want to convert filenames to UTF-8
-- Dat: fs can contain only ASCII (0..127) chars, except for `:'
-- Dat: it is good that the UNIQUE property of shortname is checked by MySQL
-- Dat: both Linux and MySQL have a limit of 255 in filenames (for shortname)
-- SUXX: cannot add a UNIQUE index on a VARCHAR(256) column...
-- SUXX: `Specified key was too long; max key length is 767 bytes' (for UNIQUE indexes),
--       so we avoid UNIQUE indexes
CREATE TABLE files (
  principal VARBINARY(32000) NOT NULL,
  shortname VARBINARY(255) NOT NULL UNIQUE,
  shortprincipal VARBINARY(255) NOT NULL,
  ino INTEGER UNSIGNED NOT NULL,
  fs VARBINARY(127) NOT NULL,
  descr TEXT NOT NULL,
  INDEX(shortprincipal),
  INDEX(principal(32000)),
  UNIQUE(ino,fs)
) ENGINE=InnoDB;

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
DROP TABLE IF EXISTS tags;
CREATE TABLE tags (
  ino INTEGER UNSIGNED NOT NULL,
  fs VARBINARY(127) NOT NULL,
  tag VARCHAR(255),
  UNIQUE(tag,ino,fs),
  UNIQUE(ino,fs,tag)
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
DROP TABLE IF EXISTS fss;
CREATE TABLE fss (
  fs VARBINARY(127) NOT NULL UNIQUE,
  mpoint VARBINARY(32000) NOT NULL,
  dev INTEGER UNSIGNED NOT NULL UNIQUE,
  root_ino INTEGER UNSIGNED NOT NULL,
  top_ino INTEGER UNSIGNED NOT NULL,
  CHECK(fs<>''),
  CHECK(mpoint<>''),
  INDEX(mpoint)
) ENGINE=InnoDB;
