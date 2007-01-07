#! /usr/local/bin/perl -w
#
# mmfs_fuse.pl -- a searchable filesystem metadata store for Linux
# by pts@fazekas.hu at Thu Jan  4 20:07:30 CET 2007
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# mmfs_fuse.pl implements the FUSE server part of movemetafs.
# movemetafs is a searchable filesystem metadata store for Linux, which lets
# users tag local files (including image, video, audio and text files) by
# simply moving the files to a special folder using any file manager, and it
# also lets users find files by tags, using a boolean search query. The
# original files (and their names) are kept intact. movemetafs doesn't have
# its own user interface, but it is usable with any file manager.
#
# See more information in README.txt.
#
# Dat: mmfs_fuse.pl is derived from fuse1.pl
# Dat: to increase performance, run with --quiet
# Dat: to use, start `fuse1.pl /tmp/mpoint' -- and, after exiting from this
#      Perl script, run `fusermount -u f'.
# Dat: see `perldoc Fuse' for more info
# Dat: similar to rofs (in C): http://mattwork.potsdam.edu/rofs
# Dat: why cannot we read /dev/null (not because it is owned by root, but
#      because it is a device -- access prevented by the FUSE kernel),
#      because of the default nosuid,nodev options
# Dat: when Fuse server dies: ls: .: Transport endpoint is not connected
#      Must umount by hand (by fusermount -u mpoint), and it is possible
#      to start a new server only after the umount.
# Dat: if the fuse server process aborts instead of replying, the client gets:
#      Software caused connection abort
# Dat: FUSE removes trailing slash from e.g. $fn of my_getattr. Good.
# Dat: FUSE is smart enough so GETDIR gets / instead of $mount_point, so we
#      can avoid the deadlock. But we nevertheless hide $mount_point inside
#      $mount_point.
# Dat: FUSE always calls GETATTR first, so open() usually doesn't report
#      Errno::ENOENT, because GETATTR has already done it.
# Dat: we use UTF-8 Perl strings, not Unicode ones (the utf8 flag is off)
# Dat: both , and AND are good for SQL UPDATE ... SET ...
# Dat: `CREATE TABLE tags_backup AS SELECT * FROM tags;' doesn't copy indexes
# Dat: policy: my_*() functions don't call db_*(), but only mydb_() directly
# Dat: policy: we never search `WHERE principal=?' because of files with
#      multiple hard links
#
package MMFS;
use Cwd;
use Fuse ':xattr';
use integer;
use strict;
use DBI;
#use DBD::mysql; # Dat: automatic for DBI->connect

use vars qw($VERSION); # Dat: see also CVS ID 
BEGIN { $VERSION='0.04' }

use vars qw($DEBUG);
$DEBUG=1;


# --- Generic functions

sub fnq($) {
  #return $_[0] if substr($_[0],0,1)ne'-'
  return $_[0] if $_[0]!~m@[^-_/.0-9a-zA-Z]@;
  my $S=$_[0];
  $S=~s@'@'\\''@g;
  "'$S'"
}

#** Dat: this is Linux-specific (NR_mknod), while FUSE works on FreeBSD, too
#** Dat: would need nonstandard Unix::Mknod.
sub mknod($$$) {
  my($fn,$mode,$rdev)=@_;
  require 'syscall.ph';
  syscall(SYS_mknod(), $fn, $mode, $rdev); # Imp: 64-bit
}

sub verify_utf8($) {
  my($S)=@_;
  die "bad UTF-8 string\n" if $S!~/\A(?:[\000-\177]+|[\xC0-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF7][\x80-\xBF]{3})*\Z(?!\n)/;
  undef
}

# --- Configuration functions

my %config;
my $config_fn='movemetafs.conf'; # !! change in the command line

sub config_reread() {
  die unless open my($F), '<', $config_fn;
  %config=();
  my $line;
  while (defined($line=<$F>)) {
    next if $line!~/\S/ or $line=~/\A\s*\#/;
    my($key,$val);
    die "missing key in config file: $config_fn, line $.\n" unless
      $line=~s@\A\s*([^\s:=]+)\s*[:=]\s*@@;
    $key=$1;
    if ($line=~m@\A"((?:[^\\"]+|\\.)*)"\s*\Z(?!\n)@s) {
      $val=$1;
      $val=~s@\\(.)@ $1 eq 'n' ? "\n" : $1 eq 't' ? "\t"
        : $1 eq 'r' ? "\r" : $1 @ges; # Imp: more, including \<newline>
    } else {
      $val=$line; $val=~s@\s+\Z(?!\n)@@;
    }
    die "duplicate key in config file: $config_fn, line $.\n" if
      exists $config{$key};
    $config{$key}=$val
  }
  undef
}

sub config_get($;$) {
  my($key,$default)=@_;
  config_reread() if !%config;
  defined $config{$key} ? $config{$key} : $default
}

# --- Generic MySQL database functions

my $dbh;

# !! 10000000  seems to be unstable
my $db_big_31bit=10000;
# vvv Dat: too big, malloc() causes abort in MySQL server
#my $db_big_31bit=2100000000;


#** @return :DBI::db
sub db_connect() {
  if (!ref $dbh) {
    # vvv Dat: needs MySQL (dbi:mysql:..., cpan DBD::mysql)
    $dbh=DBI->connect(
      config_get('db.dsn'), config_get('db.username'), config_get('db.auth'),
      { #defined $attrs{RootClass} ? ( RootClass => $attrs{RootClass} ) : (),
        RaiseError=>1, PrintError=>0, AutoCommit=>1 });
    die if !ref $dbh; # Dat: not reached, error already raised
    # Imp: adjust connection timeout to high value
    # vvv Dat: auto reconnect needs AutoComment=>1, see `perldoc DBD::mysql'
    $dbh->{mysql_auto_reconnect}=1; # Imp: verify...
    die unless db_do(q(SET NAMES 'utf8' COLLATE 'utf8_general_ci'));
    my $N=1;
    my $sql;
    while (defined($sql=config_get("db.onconnect.$N"))) {
      die unless db_do($sql);
      $N++
    }
  }
  $dbh
}


#** Dat: it is not necessary to call $sth->finish() after all rows have been
#**      fetched
#** @param rest-@_ @bind_params
#sub DBI::db::query {
#  my($dbh_self,$sql)=splice(@_,0,2);
sub db_query {
  my($sql)=shift; my $dbh_self=($dbh or db_connect());
  my $sth=$dbh_self->prepare_cached($sql,undef,1); # Imp: 3 is safer than 1 -- do we need it?
  $sth->execute(@_);
  $sth
}

#** Like $dbh->selectall_arrayref(), but uses $dbh->prepare_cached(), and
#** doesn't need \%attr
sub db_query_all {
  db_query(@_)->fetchall_arrayref()
}

#** Like $dbh->do(), but uses $dbh->prepare_cached(), and
#** doesn't need \%attr
sub db_do {
  my($sql)=shift; my $dbh_self=($dbh or db_connect());
  my $sth=$dbh_self->prepare_cached($sql,undef,1); # Imp: 3 is safer than 1 -- do we need it?
  my $rv=$sth->execute(@_); # Imp: caller() on error
  $sth->finish();
  $rv
}

#** See mysql/mysqld_ername.h
sub ER_DUP_ENTRY() { 1062 }

#** @param $maybe_p proceed if already inside a transaction
sub db_transaction($;$) {
  my($sub,$maybe_p)=@_;
  my $ret;
  if (!db_connect()->{AutoCommit}) {
    die "already in transaction\n" if !$maybe_p;
    $ret=$sub->();
  } else {
    $dbh->begin_work();
    $ret=eval { $sub->() }; # Imp: wantarray()
    if ($@) {
      $dbh->rollback() if !$dbh->{AutoCommit};
      die $@;
    } else {
      $dbh->commit() if !$dbh->{AutoCommit};
    }
  }
  $ret
}

# -- movemetafs-specific database routines (mydb_*())

my $all_fs=config_get('all.fs','F'); # !!
my $all_dev; # st_dev of "$root_prefix/."
die if 0==length($all_fs);

sub verify_tag($) {
  my($tag)=@_;
  die "bad tag\n" if $tag!~/\A[0-9a-zA-Z_\x80-\xFF]{1,255}\Z(?!\n)/; # Dat: $tag_re elsewhere
  verify_utf8($tag);
  undef
}

sub verify_tag_query_string($) {
  my($tag)=@_;
  # Dat: although MySQL allows "word1 followed by word2", we also allow `"',
  #      despite the fact that it is pointless to match on tag order,
  #      but `"' allows exact, case sensitive match.
  die "bad tag query string: bad chars or bad length\n" if
    $tag!~/\A[- +<>()~*"0-9a-zA-Z_\x80-\xFF]{1,255}\Z(?!\n)/; # Dat: $tag_re elsewhere
  die "bad tag query string: only space\n" if $tag!~/\S/;
  # ^^^ Imp: allow and remove single quotes (?) for mc(1) cd '...'
  verify_utf8($tag);
  undef
}

sub mydb_insert_tag($) {
  my($tag)=@_;
  verify_tag($tag);
  #my $rv=db_do("INSERT INTO tags (tag,ino,fs) VALUES (?,0,'') ON DUPLICATE KEY UPDATE tag=?", $tag, $tag) };
  # Dat: $rv==1: inserted, $rv==2: updated. Where is this documented?
  eval { db_do("INSERT INTO tags (tag,ino,fs) VALUES (?,0,'')", $tag) };
  die "tag already exists\n" if $@ and $dbh->err==ER_DUP_ENTRY;
  die $@ if $@;
  undef
}

sub mydb_delete_tag($) {
  my($tag)=@_;
  verify_tag($tag);
  db_connect()->begin_work();
  my $sth=db_query("SELECT 1 FROM tags WHERE tag=? AND fs<>'' LIMIT 1",$tag);
  if ($sth->fetchrow_array()) {
    $sth->finish();
    db->rollback();
    die "tag is in use\n";
  }
  $sth->finish();
  my $num_rows=0+db_do("DELETE FROM tags WHERE tag=?", $tag);
  $dbh->commit();
  die "tag not found\n" if !$num_rows;
  #die "tag already exists" if $dbh->err==ER_DUP_ENTRY;
  #die $@ if $@;
  undef
}

sub mydb_have_tag($) {
  my($tag)=@_;
  return 0 if $tag=~/\s\Z(?!\n)/;
  # ^^^ Dat: MySQL utf8_general_ci thinks 'foo'='foo ', but we don't want to
  #     find tags with spaces at the end
  print STDERR "DB_HAVE_TAG($tag)\n" if $DEBUG;
  # Imp: is COUNT(*) faster?
  my $sth=db_query("SELECT 1 FROM tags WHERE tag=? LIMIT 1",$tag);
  my $ret=($sth->fetchrow_array()) ? 1 : 0;
  print STDERR "DB_HAVE_TAG($tag) = $ret\n" if $DEBUG;
  $sth->finish();
  $ret
}

#** @return :List(String) tags
sub mydb_list_tags() {
  print STDERR "DB_LIST_TAGS()\n" if $DEBUG;
  # vvv Dat: this would return tags without the fs=''
  #map { $_->[0] } @{db_query_all(
  #  "SELECT tag FROM tags GROUP BY tag ORDER BY tag")}
  map { $_->[0] } @{db_query_all(
    "SELECT tag FROM tags WHERE ino=0 AND fs=''")}
}

#my $sth=db_query("SHOW TABLES");
#my $ar;
#while ($ar=$sth->fetchrow_arrayref()) { print "@$ar.\n" }
#print "qdone\n";
#$sth=db_query("SHOW TABLES");
#while ($ar=$sth->fetchrow_arrayref()) { print "@$ar.\n" }
#print "qdone\n";
#mydb_insert_tag("vacation");
#mydb_delete_tag("vacation");

#** @param $_[0] shortname
sub shorten_with_ext_bang($) {
  my $ext=''; $ext=$1 if $_[0]=~s@([.][^.]{1,15})\Z(?!\n)@@;
  die if length($ext)>16;
  substr($_[0],255-length($ext))='' if length($_[0])>255-length($ext);
  $_[0].=$ext;
  undef
}

#** @return :Boolean
#sub db_have_other_shortprincipal($$$) {
##  my($shortprincipal,$fs,$ino)=@_;
#  # vvv Imp: faster than COUNT(*)?
#  my $L=db_query_all(
#    "SELECT COUNT(*) FROM files WHERE shortprincipal=? AND (ino<>? OR fs<>?)",
#    $shortprincipal, $ino,$fs);
#  $L->[0][0]
#}

#** @return ($shortprincipal,$shortname) :Strings
sub mydb_gen_shorts($$$) {
  my($principal,$fs,$ino)=@_;
  #if (!defined $ino or $ino=~/\D/) { require Carp; carp("foo") }
  my $shortprincipal=$principal;
  $shortprincipal=~s@\A.*/@@s;
  shorten_with_ext_bang($shortprincipal);
  my $shortname=$shortprincipal;

  my $use_longer_p=($shortprincipal=~m@\A:[0-9a-f]+:@) ? 1 : 0;
  # ^^^ !! is it always correct if our or other shortprincipal starts with m@\A:[0-9a-f]+:@
  print STDERR "SEARCHING FOR SIMILARS to shortprincipal=($shortprincipal) fs=($fs) ino=$ino.\n" if $DEBUG;
  my $sth=db_query("SELECT fs, ino, shortname FROM files WHERE shortprincipal=? AND NOT (ino=? AND fs=?)",
    $shortprincipal, $ino, $fs);
  my($fs1,$ino1,$shortname0);
  my @sql_updates;
  while (($fs1,$ino1,$shortname0)=$sth->fetchrow_array()) {
    my $shortname1=$shortprincipal;
    $use_longer_p=1;
    print STDERR "SIMILAR SHORTNAME fs=($fs1) ino=$ino1 $shortname1.\n" if $DEBUG;
    my $prepend1=sprintf(":%x:%s:",$ino1,$fs1);
    ##print STDERR "prepend1=$prepend1\n";
    die if length($prepend1)>127;
    substr($shortname1,0,0)=$prepend1; # Dat: not largefile-safe
    shorten_with_ext_bang($shortname1);
    print STDERR "SIMILAR SHORTNAME CHANGING TO $shortname1.\n" if $DEBUG;
    push @sql_updates, ["UPDATE files SET shortname=? WHERE ino=? AND fs=?",
      $shortname1, $ino1, $fs1] if $shortname1 ne $shortname0;
  }
  undef $sth;
  # vvv Imp: enter transaction if not already in one (we're in one!)
  ##print STDERR "SQU=(@sql_updates)\n";
  for my $sql (@sql_updates) { &db_do(@$sql) }
  # $dbh->commit(); die "ZZ";
  if ($use_longer_p) {
    my $prepend=sprintf(":%x:%s:",$ino,$fs);
    die if length($prepend)>127;
    substr($shortname,0,0)=$prepend; # Dat: not largefile-safe
    shorten_with_ext_bang($shortname);
  }
  #print "GEN DONE\n";
  ($shortprincipal,$shortname)
}

#** :String. Empty or ends with slash. May start with slash. Doesn't contain
#** a double slash. Empty string means current folder.
#** $root_prefix specifies the real filesystem path to be seen in
#** "$mpoint/root"
my $root_prefix='';

#** Also verify_principal().
sub verify_localname($) {
  my($localname)=@_;
  die "empty localname\n" if !defined $localname or 0==length($localname);
  die "bad slashes in localname: $localname\n" if
    substr($localname,0,1)eq'/' or
    substr($localname,-1)eq'/' or index($localname,'//')>=0;
}

#** Dat: change this to have multiple filesystem support
#** @return ($fs,$ino)
sub file_localname_to_fs_ino($;$) {
  my($localname,$allow_nonfile_p)=@_;
  my @st;
  die "localname not found\n" unless @st=lstat($root_prefix.$localname);
  die "localname not a file\n" if !$allow_nonfile_p and !-f _;
  die "localname on different filesystem\n" if $st[0] ne $all_dev;
  ($all_fs,$st[1]) # Imp: better than $all_fs
}

#** Dat: change this to have multiple filesystem support
sub file_st_to_fs_ino($$) {
  my($st_dev,$st_ino)=@_;
  #die "localname not a file\n" if !$allow_nonfile_p and !-f _;
  die "localname on different filesystem\n" if $st_dev ne $all_dev;
  ($all_fs,$st_ino) # Imp: better than $all_fs
}

#** Doesn't do any insert if ($fs,$ino) already exists in `files'.
#** @in running in a transaction
sub mydb_insert_fs_ino_principal($$$) {
  my($fs,$ino,$principal)=@_;
  # vvv Imp: is COUNT(*) or LIMIT 1 faster?
  # vvv Dat: we mustn't check for `AND principal=$principal' here, because of
  #     files with multiple hard links
  if (0==db_query_all("SELECT COUNT(*) FROM files WHERE ino=? AND fs=?", $ino, $fs)->[0][0]) {
    # Dat: with transactions, this ensures that the same $principal is not inserted twice (really?? !! test it)
    my($shortprincipal,$shortname)=mydb_gen_shorts($principal,$fs,$ino); # Dat: this modifies the db and it might die()
    # !! what if `principal' and `fs--ino' gets out of sync?
    #    ON DUPLICATE KEY [principal] UPDATE principal=?, shortname=VALUES(shortname), shortprincipal=VALUES(shortprincipal)
    #print STDERR "INO=$ino\n";
    db_do("INSERT INTO files (principal,shortname,shortprincipal,ino,fs) VALUES (?,?,?,?,?)",
      $principal, $shortname, $shortprincipal, $ino, $fs); # Dat: this shouldn't die()
  }
}

#** Ensures that table `files' contains $localname. Searches by ($fs,$ino).
#** If not contains inserts $localname as `files.principal'.
sub mydb_ensure_fs_ino_name($$$) {
  my($fs,$ino,$localname)=@_;
  verify_localname($localname);
  db_transaction(sub {
    ($fs,$ino)=file_localname_to_fs_ino($localname) if !defined$ino; # Dat: this might die()
    mydb_insert_fs_ino_principal($fs,$ino,$localname);
  },1);
}

#** Deletes a row from tables `files' if the row doesn't contain useful
#** information.
#** @in No tags are associated with the file, tags don't have to be checked.
sub mydb_delete_from_files_if_no_info($$) {
  my($fs,$ino)=@_;
  print STDERR "DB_DELETE ino=$ino fs=($fs)\n" if $DEBUG;
  db_do("DELETE FROM files WHERE ino=? AND fs=? AND descr=''", $ino, $fs);
  # !! shorten other files with the same shortprincipal
}

#** @in running in a transaction
sub mydb_delete_from_files_if_no_info_and_tags($$) {
  my($fs,$ino)=@_;
  if (!@{db_query_all("SELECT 1 FROM tags WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) {
    mydb_delete_from_files_if_no_info($fs,$ino);
  }
}

#** Changes files.principal.
sub mydb_rename_fn($$) {
  my($oldfn,$fn)=@_;
  print STDERR "DB_RENAME_FN oldfn=($fn) fn=($fn)\n" if $DEBUG;

  my $oldlocalname=$oldfn;
  die "not a mirrored filename\n" if $oldlocalname!~s@\A/root/+@@;
  my $oldshortprincipal=$oldlocalname;
  $oldshortprincipal=~s@\A.*/@@s;
  shorten_with_ext_bang($oldshortprincipal);

  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@;
  my $shortprincipal=$localname;
  $shortprincipal=~s@\A.*/@@s;
  shorten_with_ext_bang($shortprincipal);
  my($fs,$ino)=eval { file_localname_to_fs_ino($localname) }; # Dat: this might die()
  return if $@; # Dat: maybe 'localname not a file' -- must exist, we've just renamed (!! Imp: avoid race condition)

  my $rv;
  if ($oldshortprincipal eq $shortprincipal) { # Dat: shortcut: last filename component doesn't change
    print STDERR "RENAME_FN QUICK TO principal=($localname) ino=$ino fs=($fs)\n" if $DEBUG;
    $rv=db_do("UPDATE files SET principal=? WHERE ino=? AND fs=?",
      $localname, $ino, $fs); # Dat: might have no effect
    print STDERR "RENAME_FN QUICK TO principal=($localname) ino=$ino fs=($fs) affected=$rv\n" if $DEBUG;
  } else {
    db_transaction(sub {
      print STDERR "RENAME_FN TO principal=($localname) ino=$ino fs=($fs)\n" if $DEBUG;
      my($shortprincipal,$shortname)=mydb_gen_shorts($localname,$fs,$ino); # Dat: this modifies the db and it might die()
      $rv=db_do("UPDATE files SET principal=?, shortprincipal=?, shortname=? WHERE ino=? AND fs=?",
        $localname, $shortprincipal, $shortname, $ino, $fs); # Dat: might have no effect
      print STDERR "RENAME_FN TO principal=($localname) shortprincipal=($shortprincipal) shortname=($shortname) ino=$ino fs=($fs) affected=$rv\n" if $DEBUG;
    });
  }
  $rv
}

sub mydb_fn_is_principal($) {
  my($fn)=@_;
  my $principal=$fn;
  die "not a mirrored filename\n" if $principal!~s@\A/root/+@@;
  @{db_query_all("SELECT 1 FROM files WHERE principal=? LIMIT 1",$principal)} ? 1 : 0
}

#** Does a simple scan on the string.
#** @return :String or undef
sub spec_symlink_get_shortname($) {
  my($fn)=@_;
  $fn=~m@\A/(?:tagged|search)/[^/]+/([^/]+)\Z(?!\n)@ ? $1 : undef
}

#** @param $fn filename to FUSE handler functions (staring with `/', inside
#**   --mount-point=)
#** @return :String localname (principal for `tag/.../...') or undef
sub mydb_fn_to_localname($) {
  my($fn)=@_;
  return $fn if $fn=~s@\A/root/+@@;
  my $shortname=spec_symlink_get_shortname($fn);
  return undef if !defined $shortname;
  my $L=db_query_all("SELECT principal FROM files WHERE shortname=?",
    $shortname);
  print STDERR "DB_FN_TO_LOCALNAME shortname=($shortname) got=$L (@$L).\n" if $DEBUG;
  @$L ? $L->[0][0] : undef
}


#** Dat: no-op if the file already has the tag specified
sub mydb_op_tag($$) {
  my($fn,$tag)=@_;
  die if !defined $tag;
  db_transaction(sub {
    my $localname=mydb_fn_to_localname($fn);
    die "not pointing to a mirrored filename\n" if !defined$localname;
    # vvv Dat: this check is superfluous since FUSE has checked with
    #     GETATTR() anyway, and returned Errno::ENOENT if missing
    die "unknown tag\n" if !@{db_query_all(
      "SELECT 1 FROM tags WHERE tag=? AND ino=0 AND fs='' LIMIT 1", $tag)};
    print STDERR "DB_OP_TAG localname=($localname) tag=($tag)\n" if $DEBUG;
    # Imp: implement file_shortname_to_fs_ino() in addition to
    #      file_localname_to_fs_ino() to avoid extra database access
    my($fs,$ino)=file_localname_to_fs_ino($localname); # Dat: this might die()
    print STDERR "DB_OP_TAG localname=($localname) tag=($tag) ino=$ino fs=($fs)\n" if $DEBUG;
    mydb_ensure_fs_ino_name($fs,$ino,$localname);
    # vvv Dat: different when row already present
    # vvv Dat: `ON DUPLICATE KEY UPDATE' is better than `REPLACE', because
    #     REPLACE deletes 1st
    # vvv Dat: `ON DUPLICATE KEY UPDATE' is better tgen `INSERT ... IGNORE',
    #     because `INSER ... IGNORE' ignores other errors, too
    my $rv=db_do("INSERT INTO tags (ino, fs, tag) VALUES (?,?,?) ON DUPLICATE KEY UPDATE tag=tag",
      $ino, $fs, $tag);
    mydb_update_taggings_for($fs,$ino) if $rv==1; # Dat: $rv==2: updated, $rv==1: inserted
    print STDERR "DB_OP_TAG localname=($localname) tag=($tag) ino=$ino fs=($fs) rv=$rv\n" if $DEBUG;
  });
}


sub mydb_op_untag($$) {
  my($fn,$tag)=@_;
  die if !defined $tag;
  db_transaction(sub { # Imp: is it faster without a transaction?
    my $localname=mydb_fn_to_localname($fn);
    die "not pointing to a mirrored filename\n" if !defined$localname;
    print STDERR "DB_OP_UNTAG localname=($localname) tag=($tag)\n" if $DEBUG;
    my($fs,$ino)=file_localname_to_fs_ino($localname,1); # Dat: this might die()
    print STDERR "DB_OP_UNTAG localname=($localname) tag=($tag) ino=$ino fs=($fs)\n" if $DEBUG;
    my $rv=($tag eq ':all') ?
      db_do("DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs) :
      db_do("DELETE FROM tags WHERE ino=? AND fs=? AND tag=?", $ino, $fs, $tag);
    print STDERR "DB_OP_UNTAG localname=($localname) tag=($tag) ino=$ino fs=($fs) rv=$rv\n" if $DEBUG;
    if ($rv or $tag eq ':all') { # actiually removed a tag
      mydb_delete_from_taggings_for($fs,$ino,$tag);
      if (!@{db_query_all("SELECT 1 FROM tags WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) {
        mydb_delete_from_files_if_no_info($fs,$ino);
      }
    }
  },1);
}

sub mydb_op_untag_shortname($$) {
  my($shortname,$tag)=@_;
  die if !defined $tag;
  print STDERR "DB_OP_UNTAG_SHORTNAME shortname=($shortname) tag=($tag)\n" if $DEBUG;
  db_transaction(sub { # Imp: is it faster without a transaction?
    my $R=db_query_all("SELECT fs, ino FROM files WHERE shortname=? LIMIT 1", $shortname);
    if (@$R) {
      my($fs,$ino)=@{$R->[0]};
      print STDERR "DB_OP_UNTAG_SHORTNAME shortname=($shortname) tag=($tag) ino=$ino fs=($fs)\n" if $DEBUG;
      my $rv=($tag eq ':all') ?
        db_do("DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs) :
        db_do("DELETE FROM tags WHERE ino=? AND fs=? AND tag=?", $ino, $fs, $tag);
      print STDERR "DB_OP_UNTAG_SHORTNAME shortname=($shortname) tag=($tag) ino=$ino fs=($fs) rv=$rv\n" if $DEBUG;
      if ($rv or $tag eq ':all') { # actiually removed a tag
        mydb_delete_from_taggings_for($fs,$ino,$tag);
        if (!@{db_query_all("SELECT 1 FROM tags WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) {
          mydb_delete_from_files_if_no_info($fs,$ino);
        }
      }
    }
  });
}

#** @return :List(String) List of files.shortname (symlink names)
sub mydb_find_tagged_shortnames($) {
  my($tag)=@_;
  # Dat: I don't think we should `ORDER BY shortname', the user doesn't care
  #      anyway.
  map { $_->[0] } @{db_query_all(
    "SELECT shortname FROM tags, files WHERE tags.tag=? AND tags.ino=files.ino AND tags.fs=files.fs",
    $tag)}
}

#** @return :List(String) List of files.shortname (symlink names)
sub mydb_get_shortnames() {
  my($tag)=@_;
  map { $_->[0] } @{db_query_all("SELECT shortname FROM files")}
}

# vvv Dat: double space would be needed for REPLACE(tagtxt,' foo ',' bar '),
#     but ' foo ' is not twice part of tagtxt anyway
my $mydb_concat_tags_sqlpart="CONCAT(' ',GROUP_CONCAT(CONCAT(tag,IF(CHAR_LENGTH(tag)<4,IF(CHAR_LENGTH(tag)<3,IF(CHAR_LENGTH(tag)<2,'qqa','qb'),'k'),'q')) ORDER BY tag SEPARATOR ' '),' ')";

#** See also $mydb_concat_tags_sqlpart
#** Dat: elsewhere use the property that tag_to_tagq() appends
sub tag_to_tagq($) {
  my($tag)=@_;
  $tag.(length($tag)<4 ? (length($tag)<3 ? (length($tag)<2 ? 'qqa' : 'qb') :
    'k') : 'q')
}  

#** Dat: this might be sloow
sub mydb_repair_taggings() {
  # !! test with long and lot of tags
  # vvv Dat: no serious need of transaction on `taggings')
  print STDERR "DB_REPAIR_TAGGINGS\n" if $DEBUG;
  db_transaction(sub {
    db_do("DELETE FROM taggings WHERE NOT EXISTS (SELECT * FROM tags WHERE ino=taggings.ino AND fs=taggings.fs)");
    #db_do("SET SESSION group_concat_max_len = $db_big_31bit"); # !!
    # vvv Dat: this is quite fast on 10000 rows
    # vvv Dat: good, doesn't insert empty `tags'
    # !! this makes mysqld crash because of huge group_concat_max_len
    my $rv=db_do("INSERT INTO taggings (fs, ino, tagtxt)
      SELECT fs, ino, $mydb_concat_tags_sqlpart FROM tags
      WHERE fs<>'' GROUP BY ino, fs
      ON DUPLICATE KEY UPDATE tagtxt=VALUES(tagtxt)");
    print STDERR "DB_REPAIR_TAGGINGS affected=$rv\n" if $DEBUG;
  });
}

sub mydb_delete_from_taggings_for($$$) {
  my($fs,$ino,$tag)=@_;
  if ($tag eq ':all') {
    db_do("DELETE FROM taggings WHERE ino=? AND fs=?", $ino, $fs);
  } else {
    mydb_update_taggings_for($fs,$ino);
  }
}

#** Dat: this might be sloow
sub mydb_update_taggings_for($$) {
  my($fs,$ino)=@_;
  # vvv Dat: no serious need of transaction on `taggings')
  print STDERR "DB_UPDATE_TAGGINGS ino=$ino fs=($fs)\n" if $DEBUG;
  db_transaction(sub {
    my $rv="none";
    if (!@{db_query_all("SELECT 1 FROM tags WHERE ino=? AND fs=?", $ino, $fs)}) {
      # ^^^ Dat: if SELECT below returns empty resultset? -> nothing is inserted
      db_do("DELETE FROM taggings WHERE ino=? AND fs=?", $ino, $fs);
    } else {
      db_do("SET SESSION group_concat_max_len = $db_big_31bit");
      $rv=db_do("INSERT INTO taggings (fs, ino, tagtxt)
        SELECT fs, ino, $mydb_concat_tags_sqlpart FROM tags
        WHERE ino=? AND fs=? GROUP by ino, fs
        ON DUPLICATE KEY UPDATE tagtxt=VALUES(tagtxt)", $ino, $fs);
    }
    print STDERR "DB_UPDATE_TAGGINGS affected=$rv\n" if $DEBUG;
  }, 1);
}

sub mydb_rename_tag($$) {
  my($oldtag,$newtag)=@_;
  # vvv Dat: this is for GNU mv(1) for `mv meta/tag/old "meta/tag/existing "'
  $newtag=~s@\A\s+@@;  $newtag=~s@\s+\Z(?!\n)@@;
  verify_tag($oldtag);
  verify_tag($newtag);
  # vvv Dat: Linux rename(2) succeeds for $oldfn eq $newfn, so do we.
  return if $oldtag eq $newtag;
  db_transaction(sub {
    # vvv Dat: this doesn't work if a file has both $newtag, $oldtag
    # vvv Dat: `IGNORE' prevents the update when a duplicate key constraint
    #     is violated
    my $rv=db_do("UPDATE IGNORE tags SET tag=? WHERE tag=?", $newtag, $oldtag);
    db_do("DELETE FROM tags WHERE tag=?", $oldtag);
    print STDERR "DB_RENAME_TAG oldtag=($oldtag) newtag=($newtag) affected=($rv)\n" if $DEBUG;
    if ($rv) {
      my $oldtagq=tag_to_tagq($oldtag);
      my $newtagq=tag_to_tagq($newtag);
      # vvv Dat: need not be in a transaction with the UPDATE above, table
      #     `taggings' is not transactional
      # vvv Imp: maybe regenerate all affected lines in taggings
      db_do("UPDATE taggings SET tagtxt=REPLACE(REPLACE(tagtxt,?,' '),?,?) WHERE MATCH(tagtxt) AGAINST (?)",
        " $newtagq ", " $oldtagq ", " $newtagq ", $oldtagq);
    }
  });
}

#** @return :List(String) List of files.shortname in decreasing order of
#**   MySQL fulltext index relevance
sub mydb_find_files_matching($) {
  my($qs)=@_;
  verify_tag_query_string($qs);
  my $qsq=$qs;
  # vvv Dat: this also works for word*
  # vvv Dat: here we use the property that tag_to_tagq() appends
  $qsq=~s@([0-9a-zA-Z_\x80-\xFF]+)([*]?)@
    0==length($2) ? tag_to_tagq($1) : $1.$2 @ge; # Dat: $tag_re elsewhere
  my $in_boolean_mode=($qsq=~m@[^\s0-9a-zA-Z_\x80-\xFF]@) ? # Dat: $tag_re elsewhere
    " IN BOOLEAN MODE" : "";
  print STDERR "DB_FIND_TAGGED_SHORTNAMES$in_boolean_mode qsq=($qsq)\n" if $DEBUG;
  my $ret=db_query_all(
    "SELECT shortname FROM taggings, files WHERE MATCH (tagtxt) AGAINST (?$in_boolean_mode) AND taggings.ino=files.ino AND taggings.fs=files.fs",
    $qsq);
  for my $shortname (@$ret) { $shortname=$shortname->[0] }
  # vvv Dat: search results of 8000 files takes up to 0.3s to transfer -- slow?
  print STDERR "DB_FIND_TAGGED_SHORTNAMES found ".scalar(@$ret)." files\n" if $DEBUG;
  @$ret
}

sub mydb_get_principal($) {
  my $shortname=$_[0];
  my $R=db_query_all("SELECT principal FROM files WHERE shortname=? LIMIT 1",
    $shortname);
  @$R ? $R->[0][0] : undef
}

#** Uses the `tags' table.
#** @return :List(String) in `ORDER BY tags'.
sub mydb_file_get_tags($) {
  my($fn)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  # Dat: this is wrong if a file has multiple links:
  #      return map { $_->[0] } @{db_query_all("SELECT tag FROM tags, files WHERE principal=? AND files.ino=tags.ino AND files.fs=tags.fs ORDER BY tag",$localname)};
  my($fs,$ino)=file_localname_to_fs_ino($localname); # Dat: this might die()
  map { $_->[0] } @{db_query_all("SELECT tag FROM tags WHERE ino=? AND fs=? ORDER BY tag",
    $ino, $fs)}
}  

#** @return :String or undef (if file is not tagged)
sub mydb_file_get_descr($) {
  my($fn)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  my($fs,$ino)=file_localname_to_fs_ino($localname); # Dat: this might die()
  my $L=db_query_all("SELECT descr FROM files WHERE ino=? AND fs=? LIMIT 1",
    $ino, $fs);
  @$L ? $L->[0][0] : undef
}

#** @return :String or undef (if file is not tagged)
sub mydb_file_set_descr($$) {
  my($fn,$descr)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  verify_utf8($descr);
  $descr=~s@\s+\Z(?!\n)@@;
  $descr=~s@\A\s+@@;
  print STDERR "DB_FILE_SET_DESCR localname=($localname) descr=($descr)\n" if $DEBUG;
  db_transaction(sub {
    my($fs,$ino)=file_localname_to_fs_ino($localname); # Dat: this might die()
    mydb_ensure_fs_ino_name($fs,$ino,$localname);
    # vvv Dat: we could do this with `WHERE fs=? AND ino=?'
    my $rv=db_do("UPDATE files SET descr=? WHERE ino=? AND fs=?", $descr, $ino, $fs);
    mydb_delete_from_files_if_no_info_and_tags($fs,$ino) if $rv and 0==length($descr);
  });
}

#** @return :String or undef (if file is not tagged)
sub mydb_file_set_tagtxt($$) {
  my($fn,$tagtxt)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  my @tags;
  while ($tagtxt=~m@(\S+)@g) { push @tags, $1; verify_tag($tags[-1]) }
  db_transaction(sub {
    print STDERR "DB_FILE_SET_TAGTXT localname=($localname) tags=(@tags)\n" if $DEBUG;
    # vvv Dat: similar to mydb_file_get_tags()
    my($fs,$ino)=file_localname_to_fs_ino($localname); # Dat: this might die()
    # vvv Dat: works even if `fs--ino' is missing from `files'
    my @old_tags=map { $_->[0] } @{db_query_all("SELECT tag FROM tags WHERE ino=? AND fs=? ORDER BY tag",
      $ino, $fs)};
    if (join(' ', sort@tags) ne join(' ', sort@old_tags)) {
      # Imp: DELETE and INSERT only the difference
      if (@tags) {
        # Dat: no problem if duplicates in @tags
        # Imp: optimize, remove duplicates
        { my %all_tags;
          # vvv Imp: don't cache statement, and use subset of @tags
          for my $row (@{db_query_all("SELECT tag FROM tags WHERE ino=0 AND fs=''")}) {
            $all_tags{$row->[0]}=1
          }
          for my $tag (@tags) { die "unknown tag: $tag\n" if !defined $all_tags{$tag} }
        }
        # Imp: implement file_shortname_to_fs_ino() in addition to
        #      file_localname_to_fs_ino() to avoid extra database access
        print STDERR "DB_FILE_SET_TAGTXT localname=($localname) tags=(@tags) ino=$ino fs=($fs)\n" if $DEBUG;
        mydb_ensure_fs_ino_name($fs,$ino,$localname);
        ## vvv Dat: different when row already present
        db_do("DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs);
        for my $tag (@tags) { # Imp: faster (cannot do w/o multiple INSERTs :-(
          db_do("INSERT INTO tags (ino, fs, tag) VALUES (?,?,?) ON DUPLICATE KEY UPDATE tag=tag",
            $ino, $fs, $tag);
          #$had_change_p=1 if $rv==1; # Dat: $rv==2: updated, $rv==1: inserted
        }
        mydb_update_taggings_for($fs,$ino); # Dat: a if $had_change_p;
      } else { mydb_op_untag($fn,':all') }
    } else {
      print STDERR "DB_FILE_SET_TAGTXT localname=($localname) tags=(@tags) unchanged\n" if $DEBUG;
    }
  });
}

#** Is unlink OK if $fn has multiple hard links?
sub mydb_may_unlink_multi() {
  my($fn)=@_;
  !mydb_fn_is_principal($fn)
}

#** Unlinks the last hard link of the file from the database.
sub mydb_unlink_last($$$) {
  my($fn,$st_dev,$st_ino)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  print STDERR "DB_UNLINK_LAST localname=($localname)\n" if $DEBUG;
  # vvv Dat: too late, deleted.
  my($fs,$ino)=file_st_to_fs_ino($st_dev,$st_ino); # Dat: this might die()
  if (@{db_query_all("SELECT 1 FROM files WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) {
    print STDERR "DB_UNLINK_LAST localname=($localname) ino=$ino fs=($fs)\n" if $DEBUG;
    db_transaction(sub {
      my $rv1=db_do(   "DELETE FROM files WHERE ino=? AND fs=?", $ino, $fs);
      my $rv2=db_do(    "DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs);
      my $rv3=db_do("DELETE FROM taggings WHERE ino=? AND fs=?", $ino, $fs);
      print STDERR "DB_UNLINK_LAST localname=($localname) ino=$ino fs=($fs) rv=$rv1+$rv2+$rv3\n" if $DEBUG;
    });
  } else {
    print STDERR "DB_UNLINK_LAST localname=($localname) ino=$ino fs=($fs) not-in-files\n" if $DEBUG;
  }
}

#die $dbh->{AutoCommit};
#db_connect()->begin_work();
##die $dbh->{AutoCommit} ? 1 : 0;
#db_connect()->rollback();
# eval { db_query("FOO BAR"); }; die "($@)";

# vvv Imp: verify all die()s, add them here
my %dienerrnos=(
  'bad tag' => -1*Errno::EINVAL, # Dat: like EINVAL when creating a file named `?' on a vfat filesystem on Linux
  'bad tag query string' => -1*Errno::EINVAL,
  'bad UTF-8 string' => -1*Errno::EINVAL,
  'tag not found' => -1*Errno::ENOENT,
  'empty localname' => -1*Errno::EINVAL,
  'bad slashes in localname' => -1*Errno::EINVAL,
  'localname not a file' => -1*Errno::ENOTSUP,
  'localname not found' => -1*Errno::ENOENT,
  'unknown tag' => -1*Errno::EADDRNOTAVAIL,
  'tag alredy exists' => -1*Errno::EEXIST,
  'tag is in use' => -1*Errno::ENOTEMPTY,
  'localname on different filesystem' => -1*Errno::EREMOTEIO, # EXDEV, # Dat: bad, mv(1) doesn't get EXDEV, but reports EREMOTEIO properly
  'DBD::mysql::st execute failed' => -1*Errno::EIO, # Dat: by db_query()
  'not a mirrored filename' => -1*Errno::EINVAL,
  'not pointing to a mirrored filename' => -1*Errno::EINVAL,
);

#** @return 0 or -1*Errno::E...
sub diemsg_to_nerrno() {
  return 0 if !$@;
  my $msg=$@;
  chomp($msg);
  print STDERR "info: diemsg: $msg\n" if $DEBUG;
  $msg=~s@(?::\s|\n).*@@s;
  ($dienerrnos{$msg} or -1*Errno::EPERM)
}


# ---

#** Absolute dir. Starts with slash. Doesn't end with slash. Doesn't contain
#** a double slash. Isn't "/".
my $mpoint;

my $read_only_p=0;

# vvv Dat: SUXX: cannot kill processes using the mount point
#     Dat: cannot reconnect
#my @do_umount;
sub cleanup_umount() {
  if (defined $mpoint) {
    system('fusermount -u -- '.fnq($mpoint).' 2>/dev/null'); # Imp: hide only not-mounted errors, look at /proc/mounts
  }
}

sub exit_signal($) {
  #** :String.
  my $sig=$_[0];
  #print STDERR "FOO\n";
  $SIG{$sig}='DEFAULT';
  cleanup_umount();
  die if 1!=kill($sig,$$);
  #print STDERR "BAR\n";
  # exit(-1); # Dat: bad, too early, since Perl blocks the signal by the kill() above since we are handling it...
}
# vvv Dat: never reached...
END { cleanup_umount(); }

# vvv Dat: doesn't work with Fuse.pm in Fuse::main -- signal handlers wont'
#     get called.
#$SIG{INT}=\&exit_signal;
#$SIG{HUP}=\&exit_signal;
#$SIG{TERM}=\&exit_signal;
#$SIG{QUIT}=\&exit_signal;
# Dat: don't hook QUIT

#** Removes /root/, prepends $root_prefix.
#** @return undef if not starting with root (or if result would start with
#**   $mpoint); filename otherwise
sub sub_to_real($) {
  my $fn=$_[0];
  return undef if $fn!~s@\A/root(?=/|\Z(?!\n))@@;
  ## Dat: now substr($fn,0,1) eq '/', so an empty root_prefix would yield /
  substr($fn,0,0)=(0==length($root_prefix)) ? '.' : $root_prefix;
  $fn="/" if 0==length($fn);
  #print STDERR "SUB_TO_REAL() real=$fn\n";
  return (substr($fn,0,length($mpoint)) eq $mpoint and
    (length($fn)==length($mpoint) or substr($fn,length($mpoint),1)eq"/") ) ?
    undef : $fn
}

# Dat: Linux-specific
# vvv Dat: from /usr/include/bits/stat.h
#define __S_IFCHR       0020000 /* Character device.  */
#define __S_IFBLK       0060000 /* Block device.  */
#define __S_IFIFO       0010000 /* FIFO.  */
#define __S_IFSOCK      0140000 /* Socket.  */
sub S_IFDIR() { 0040000 } # Directory.
sub S_IFREG() { 0100000 } # Regular file.
sub S_IFLNK() { 0120000 } # Symbolic link.

# Dat: Linux-specific
# vvv Dat: from /usr/include/bits/fcntl.h
#define O_RDWR               02
#define O_NOCTTY           0400 /* not fcntl */   
#define O_TRUNC           01000 /* not fcntl */
#define O_APPEND          02000
#define O_NONBLOCK        04000
#define O_NDELAY        O_NONBLOCK
#define O_SYNC           010000
#define O_FSYNC          O_SYNC
#define O_ASYNC          020000
sub O_ACCMODE() { 0003 }
sub O_RDONLY() { 00 }
sub O_WRONLY() { 01 }
sub O_CREAT() { 0100 }; # not fcntl
sub O_EXCL()  { 0200 }  # not fcntl

# Dat: from /usr/include/attr/xattr.h
sub Errno::ENOATTR() { Errno::ENODATA }

#** Dat: GETATTR is similar to lstat().
#** Dat: GETATTR is called for all components before an open():
#**        GETATTR(/root)
#**        GETATTR(/root/etc)
#**        GETATTR(/root/etc/fstab)
sub my_getattr($) {
  # Dat: no problem of faking a setuid bit: fusermount is nosuid by default
  my $fn=$_[0];
  my $real;
  print STDERR "GETATTR($fn)\n" if $DEBUG;
  my $dev=3; # Dat: fake /proc
  my $ino=0; # Dat: the "ino" field is currently ignored.
  my $mode=0755|S_IFDIR;
  my $nlink=1; # Dat: undocumentedly (Linux NTFS) good for dirs in GNU find(1), no need for -noleaf
  my $uid=0;
  my $gid=0;
  my $rdev=0;
  my $size=0;
  my $atime=0;
  my $mtime=0;
  my $ctime=0;
  my $blksize=4096;
  my $blocks=0;
  if ($fn eq '/') {
  # vvv Dat: top level dirs have high priority, because getattr(2) is called for them
  } elsif ($fn eq '/tag' or $fn eq '/untag' or $fn eq '/tagged',
    or $fn eq '/search') {
  } elsif ($fn eq '/root') {
  } elsif (defined($real=sub_to_real($fn))) {
    # Dat: rofs also uses lstat() instead of stat()
    my @L=lstat($real);
    return -1*$! if !@L;
    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=@L;
  } elsif ($fn=~m@\A/(tag|untag|tagged)/([^/]+)\Z(?!\n)@) { # Dat: ls(!) and zsh(1) echo tag/* needs it
    my $op=$1; my $tag=$2;
    return -1*Errno::ENOENT unless
      (($op eq 'untag' or $op eq 'tagged') and $tag eq ':all')
      or eval { mydb_have_tag($tag) };
    #$mode=($mode&0755)|S_IFDIR;
  } elsif ($fn=~m@\A/search/([^/]+)\Z(?!\n)@) { # Dat: seems to be needed for my_getdir
    #$mode=($mode&0755)|S_IFDIR;
  } elsif ($fn=~m@\A/(?:tagged|search)/([^/]+)/([^/]*)\Z(?!\n)@ and
           $2 ne '::') {
    # Dat: ls(1) and zsh(1) echo tag/* need this
    # Dat: presence of this branch is needed for `echo tag/bar/*'
    # Dat: rm meta/tag/foo/never-existing-file works (unlink() returns 0),
    #      because we are lazy here
    # Dat: our laziness doesn't prevent mv(1) from moving a file to /tag/foo/
    # Dat: our laziness causes `ls -l meta/tagged/food/blah' report a symlink,
    #      but readlink(2) returns `No such file or directory'. This is just
    #      a minor inconvenience that never shows up in graphical file
    #      managers.
    # Imp: maybe do a SELECT for each tagged file? Would be too slow...
    my $subdir=$1; my $symlink=$2;
    #return -1*Errno::ENOENT if !mydb_have_tag($subdir); # Dat: checked by the previous call, but could be changed since then...)
    $mode=($mode&0644)|S_IFLNK;
  } else {
    # Imp: Errno::EACCES for $mount_point/$mount_point
    return -1*Errno::ENOENT;
  }
  ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)
}

#** Dat: GETATTR is not called before getdir...
#** Dat: the process readdir(3) receives dirs in exactly reverse order
sub my_getdir($) {
  my $dir=$_[0];
  my $real;
  my $D;
  print STDERR "GETDIR($dir)\n" if $DEBUG;
  if ($dir eq '/') {
    # Dat: we need '.' and '..' for both / and others
    return ('.','..','root','search','tag','untag','tagged', 0); # $errno
  } elsif ($dir eq '/tag' or $dir eq '/untag' or $dir eq '/tagged') {
    my @L=eval { mydb_list_tags() };
    return diemsg_to_nerrno() if $@;
    return ('.','..',(($dir eq '/untag' or $dir eq '/tagged') ? ':all' : ()), @L, 0)
  } elsif ($dir eq '/tagged/:all') {
    my @L=eval { mydb_get_shortnames() };
    return diemsg_to_nerrno() if $@;
    return ('.','..',@L, 0);
  } elsif ($dir=~m@\A/search/([^/]+)\Z(?!\n)@) {
    my @L=eval { mydb_find_files_matching($1) };
    return diemsg_to_nerrno() if $@;
    return ('.','..',@L, 0);
  } elsif ($dir=~m@\A/(?:tag|untag)/([^/]+)\Z(?!\n)@) {
    # Dat: as of movemetafs-0.04, `meta/tag/$TAGNAME' is empty
    return ('.','..', 0);
  } elsif ($dir=~m@\A/(?:tagged)/([^/]+)\Z(?!\n)@) {
    my @L=eval { mydb_find_tagged_shortnames($1) };
    return diemsg_to_nerrno() if $@;
    return ('.','..',@L, 0);
  } elsif ($dir eq '/search' or $dir eq '/untag/:all') {
    return ('.','..',0);
  } elsif (!defined($real=sub_to_real($dir))) {
    # Dat: getdents64() returns ENOENT, but open(...O_DIRECTORY) succeeds
    return -1*Errno::ENOENT; # Imp: probably ENOTDIR
  } elsif (!opendir($D,$real)) {
    return -1*$!
  } else {
    #die "R=$real\n";
    # Imp: propagate errors
    my @ret=('.','..',readdir($D),0);
    closedir($D);
    return @ret
  }
}

#** Dat: only check whether the open is permitted.
sub my_open($$) {
  # SUXX: permission denied for other users' files (with FUSE mount...)
  # Dat: O_CREAT | O_EXCL | O_TRUNC is not passed.
  my($fn,$flags)=@_;
  print STDERR "OPEN($fn,$flags)\n" if $DEBUG;
  return -1*Errno::EROFS if $read_only_p and ($flags&O_ACCMODE)!=O_RDONLY;
  #print "OPEN_OK\n";
  return 0
}

sub my_read($$$) {
  my($fn,$size,$offset)=@_;
  my $real;
  my $F;
  #$offset=0 if !defined $offset;
  print STDERR "READ($fn,$size,$offset)\n" if $DEBUG;
  # ^^^ Dat: maximum size for FUSE READ() seems to be 131072 bytes
  # $size=999 if $size>999; # Dat: bad, short read not allowed, application
  # still received original $size
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::ENOENT; # can we return this?
  } elsif (!open($F,'<',$real)) {
    return -1*$!; # can we return everything?
  } elsif (!sysseek($F,$offset,0)) {
    return -1*$!;
  } else {
    my $S='';
    my $got=sysread($F,$S,$size);
    if (!defined $got) { close($F);  return -1*$! }
    close($F);
    #return -1*Errno::EIO if $got and $got>0 and $got<$size; # Dat: short read => near EOF
    return $S
  }
}

#** Dat: called for character nodes, block nodes, sockets, pipes and
#**      regular files
#** Dat: not called for directories and symlinks 
sub my_mknod($$$) {
  my($fn,$mode,$rdev)=@_;
  my $real;
  my $F;
  my $got;
  #$offset=0 if !defined $offset;
  print STDERR "MKNOD($fn,$mode,$rdev)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM;
#  } elsif (($mode&S_IFREG)!=0) {
#    # Dat: shortcut for regular files.
#    if (!sysopen($F,$real,(O_WRONLY|O_CREAT|O_EXCL),($mode&07777))) {
#      return -1*$!; # can we return everything?
#    }
#    close($F);
  } else {
    if (!defined($got=mknod($real,$mode,$rdev)) or $got<0) {
      return -1*$!;
    }
  }
  return 0
}

sub my_write($$$) {
  my($fn,$S,$offset)=@_;
  my $real;
  my $F;
  #$offset=0 if !defined $offset;
  print STDERR "WRITE($fn,".length($S).",$offset)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM; # can we return this?
  } elsif (!sysopen($F,$real,O_WRONLY)) { # Dat: no need for O_CREAT, already checked
  #} elsif (!open($F,'+<',$real)) { # Dat: this would open for reading (if permission denied...)
    return -1*$!; # can we return everything?
  } elsif (!sysseek($F,$offset,0)) {
    return -1*$!;
  } else {
    my $got=syswrite($F,$S,length($S));
    #print STDERR "GOT=$got.\n";
    # Dat: EBADF: not open for writing; hidden by FUSE
    if (!$got) { my $ret=($!>0 ? -1*$! : -1*Errno::EIO); close($F); return $ret }
    close($F);
    #return -1*Errno::EIO if $got and $got>0 and $got<length($S); # Dat: short read => near EOF
    return $got # Dat: undocumented Fuse.pm requirement (return # bytes written)
  }
}

sub my_unlink($) {
  my($fn)=@_;
  my $real;
  print STDERR "UNLINK($fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/(?:tagged)/([^/]+)/([^/]+)\Z(?!\n)@) {
      my $tag=$1; my $shortname=$2;
      eval { mydb_op_untag_shortname($shortname,$tag) };
      return diemsg_to_nerrno()
    }
    return -1*Errno::EPERM
  } else {
    my($st_dev,$st_ino,$st_mode,$st_nlink)=lstat($real);
    if (defined $st_nlink and $st_nlink>1) {
      # ^^^ Dat: this check has a race condition only
      my $may_p=eval { mydb_unlink_multi($fn) };
      return diemsg_to_nerrno() if $@;
      return -1*Errno::EPERM if !$may_p;
    }
    return -1*$! if !unlink($real);
    if (defined $st_nlink and $st_nlink==1) {
      # Dat: when the last (hard) link of a file is removed, remove the file
      #      from the metadata store
      eval { mydb_unlink_last($fn,$st_dev,$st_ino) };
      # vvv Dat: always succeed if remove succeeds
      #return diemsg_to_nerrno()
      print STDERR "info: error: $@" if $@;
    }
  }
  return 0
}

sub my_rmdir($) {
  my($fn)=@_;
  my $real;
  print STDERR "RMDIR($fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/(?:tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
      my $tag=$1;
      eval { mydb_delete_tag($tag); };
      return diemsg_to_nerrno();
    }
    return -1*Errno::EPERM
  } else {
    my($st_dev,$st_ino)=lstat($real);
    if (!defined($st_ino) or !rmdir($real)) {
      return -1*$!
    } else { # Dat: no need to test for $st_nlink (>=2)
      # Imp: test this
      eval { mydb_unlink_last($fn,$st_dev,$st_ino) };
      # vvv Dat: always succeed if remove succeeds
      #return diemsg_to_nerrno()
      print STDERR "info: error: $@" if $@;
    }
    return 0
  }
}

sub my_mkdir($$) {
  my($fn,$mode)=@_;
  my $real;
  # Dat: FUSE calls: GETATTR(), MKDIR(), GETATTR()
  print STDERR "MKDIR($fn,$mode)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/(?:tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
      my $tag=$1;
      eval { mydb_insert_tag($tag); };
      return diemsg_to_nerrno();
    } elsif ($fn eq '/repair_taggings') {
      eval { mydb_repair_taggings(); };
      return diemsg_to_nerrno();
      # ^^^ Dat: although we return 0 here, FUSE will GETATTR() after MKDIR(),
      #          and return Errno::ENOENT to the application.
    }
    return -1*Errno::EPERM
  } elsif (!mkdir($real,$mode)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_chmod($$) {
  my($fn,$mode)=@_;
  my $real;
  print STDERR "CHMOD($fn,$mode)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!chmod($mode,$real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_chown($$$) {
  my($fn,$uid,$gid)=@_;
  my $real;
  print STDERR "CHOWN($fn,$uid,$gid)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!chown($uid,$gid,$real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_utime($$$) {
  my($fn,$atime,$mtime)=@_;
  my $real;
  print STDERR "UTIME($fn,$atime,$mtime)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!utime($atime,$mtime,$real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_symlink($$) {
  my($target,$fn)=@_;
  my $real;
  print STDERR "SYMLINK($target,$fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!symlink($target,$real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_link($$) {
  my($oldfn,$fn)=@_;
  my($oldreal,$real);
  print STDERR "LINK($oldfn,$fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!defined($oldreal=sub_to_real($oldfn))) {
    return -1*Errno::EXDEV
  } elsif (!link($oldreal,$real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_rename($$) {
  my($oldfn,$fn)=@_;
  my($oldreal,$real);
  print STDERR "RENAME($oldfn,$fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/(tag|untag|tagged)/([^/]+)/[^/]+\Z(?!\n)@) {
      # Dat: mydb_op_tag() and mydb_op_untag() verify if $oldfn is a mirrored filename,
      #      no need to check defined(sub_to_real($oldfn))
      my $op=$1; my $tag=$2;
      return -1*Errno::EPERM if $tag eq ':all' and $op ne 'untag';
      eval { $op eq 'tag' ? mydb_op_tag($oldfn,$tag) : mydb_op_untag($oldfn,$tag) };
      return diemsg_to_nerrno()
    } elsif ($fn=~m@/(tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
      my $op=$1; my $tag=$2;
      if ($oldfn=~m@/(tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
        my $oldop=$1; my $oldtag=$2;
        eval { mydb_rename_tag($oldtag,$tag) };
        return diemsg_to_nerrno()
      }
    }
    return -1*Errno::EPERM
  } elsif (!defined($oldreal=sub_to_real($oldfn))) {
    return -1*Errno::EXDEV
  } elsif (!rename($oldreal,$real)) {
    return -1*$!
  } else {
    eval { mydb_rename_fn($oldfn,$fn) };
    return diemsg_to_nerrno()
  }
}

sub my_readlink($) {
  my($fn)=@_;
  my $real;
  my $ret;
  print STDERR "READLINK($fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    #print STDERR "RR $fn\n";
    my $shortname=spec_symlink_get_shortname($fn);
    if (defined $shortname) {
      #print STDERR "SS $shortname\n";
      my $principal=eval { mydb_get_principal($shortname) };
      return diemsg_to_nerrno() if $@;
      return defined($principal) ? "../../root/$principal" : -1*Errno::ENOENT
    }
    return -1*Errno::EPERM
  } elsif (!defined($ret=readlink($real))) {
    # Imp: possibly translate absolute links to relative ones to avoid going up
    #      above the mountpoint
    return -1*$!
  } else {
    return $ret
  }
}

sub my_truncate($$) {
  my($fn,$tosize)=@_;
  my $real;
  print STDERR "TRUNCATE($fn,$tosize)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!truncate($real,$tosize)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_statfs() {
  print STDERR "STATFS()\n" if $DEBUG;
  return -1*Errno::ENOANO;
}

sub my_flush($) {
  my($fn)=$_[0];
  print STDERR "FLUSH($fn)\n" if $DEBUG;
  return 0;
}

sub my_fsync($) {
  my($fn)=$_[0];
  print STDERR "FSYNC($fn)\n" if $DEBUG;
  return 0;
}

sub my_release($$) {
  my($fn,$flags)=@_;
  print STDERR "RELEASE($fn)\n" if $DEBUG;
  return 0;
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_listxattr($) {
  my($fn)=@_;
  my $real;
  my @attrs;
  print STDERR "LISTXATTR($fn)\n" if $DEBUG;
  # Dat: getfattr(1) `getfattr -d' needs the "user." prefix
  if ($fn eq '/root' or !defined($real=sub_to_real($fn))) {
    # Dat: `meta/root' is also a fakenode, since it doesn't have a valid
    #      $localname
    push @attrs, 'user.fakenode';
  } else {
    push @attrs, 'user.realnode';
    push @attrs, 'user.tags'; # Dat: lazy here, even for files with no tags
    push @attrs, 'user.description'; # Dat: lazy here, even for files with an empty description
  }
  push @attrs, 0; # $errno indicator
  #print STDERR "ATTRS=@attrs\n";
  @attrs
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
#** Dat: if we return `0' from here for a attrname with my_listxattr,
#**      `getfattr -d' displays only `attrname' instead of `attrname="val"',
#**      just as if we return the empty string when @tags==0
sub my_getxattr_low($$) {
  my($fn,$attrname)=@_;
  my $real=sub_to_real($fn);
  # Imp: maybe return non-zero errno
  if ($attrname eq 'user.fakenode') {
    return defined($real) ? 0 : "1"
  } elsif ($attrname eq 'user.realnode') {
    return defined($real) ? "1" : 0
  } elsif ($attrname eq 'user.tags') {
    return 0 if !defined $real;
    my @tags=eval { mydb_file_get_tags($fn) };
    return '' if $@ eq "localname not a file\n"; # Imp: test after preprocessing
    return diemsg_to_nerrno() if $@;
    join(' ',@tags)
  } elsif ($attrname eq 'user.description') {
    return 0 if !defined $real;
    my $descr=eval { mydb_file_get_descr($fn) };
    return '' if $@ eq "localname not a file\n"; # Imp: test after preprocessing
    return diemsg_to_nerrno() if $@;
    defined$descr ? $descr : ''
  }
}

sub my_getxattr($$) {
  my($fn,$attrname)=@_;
  print STDERR "GETXATTR($fn,$attrname)\n" if $DEBUG;
  my_getxattr_low($fn,$attrname)
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
#** Dat: `setfattr -n attrname filename' => $attrval eq ""
#** Dat: `setfattr -n attrname -v notempty filename'
sub my_setxattr_low($$$$) {
  my($fn,$attrname,$attrval,$flags)=@_;
  # Dat: we can safely ignore $flags|Fuse::XATTR_CREATE and Fuse::XATTR_REPLACE
  my $real=sub_to_real($fn);
  return -1*Errno::EPERM if !defined($real);
  # Imp: maybe return non-zero errno
  if ($attrname eq 'user.tags') {
    eval { mydb_file_set_tagtxt($fn,$attrval) };
    return diemsg_to_nerrno();
  } elsif ($attrname eq 'user.description') {
    eval { mydb_file_set_descr($fn,$attrval) };
    return diemsg_to_nerrno();
  } elsif (my_getxattr_low($fn,$attrname) eq $attrval) {
    # ^^^ Imp: `eq' on error messages
    # Dat: this is so `setxattr --restore' runs cleanly on `user.realnode'
    return 0
  }
  return -1*Errno::EPERM
}

sub my_setxattr($$$$) {
  my($fn,$attrname,$attrval,$flags)=@_;
  print STDERR "SETXATTR($fn,$attrname,$attrval,$flags)\n" if $DEBUG;
  my_setxattr_low($fn,$attrname,$attrval,$flags)
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
#** Dat: `setfattr -x attrname filename'
sub my_removexattr($$) {
  my($fn,$attrname)=@_;
  print STDERR "REMOVEXATTR($fn,$attrname)\n" if $DEBUG;
  my_setxattr_low($fn,$attrname,"",0); # Imp: smarter
  # vvv Imp: disinguish "0" and 0 (with Scalar::Util?)
  #if (my_getxattr_low($fn,$attrname)eq"0") { # Dat: no such attribute
  #  return -1*Errno::ENOATTR
  #} else {
  #  return -1*Errno::EPERM
  #}
}

# --- main()

{ my $I;
  for ($I=0;$I<@ARGV;$I++) {
    if ($ARGV[$I] eq'-' or substr($ARGV[$I],0,1)ne'-') { last }
    elsif ($ARGV[$I] eq '--') { $I++; last }
    elsif ($ARGV[$I] eq '--read-only=0') { $read_only_p=0 } # Dat: default
    elsif ($ARGV[$I] eq '--read-only=1') { $read_only_p=1 }
    elsif ($ARGV[$I] eq '--verbose') { $DEBUG++ }
    elsif ($ARGV[$I] eq '--quiet'  ) { $DEBUG-- }
    elsif ($ARGV[$I]=~/--mount-point=(.*)/s) { $mpoint=$1 }
    elsif ($ARGV[$I]=~/--root-prefix=(.*)/s) { $root_prefix=$1 }
    elsif ($ARGV[$I] eq '--version') {
      print STDERR "movemetafs v$VERSION".' $Id: mmfs_fuse.pl,v 1.12 2007-01-07 00:00:05 pts Exp $'."\n";
      print STDERR "by Pe'ter Szabo' since early January 2007\n";
      print STDERR "The license is GNU GPL >=2.0. It comes without warranty. USE AT YOUR OWN RISK!\n";
      exit 0
    }
    elsif ($ARGV[$I] eq '--help') { die "$0: no --help, see README.txt\n" }
    else { die "$0: unknown option: $ARGV[$I]\n" }
  }
  splice @ARGV, 0, $I;
  die "$0: extra args\n" if @ARGV;
}
die "$0: missing --mount-point=, see README.txt\n" if !defined $mpoint or 0==length($mpoint);
die "$0: cannot find mpoint\n" if !defined($mpoint=Cwd::abs_path($mpoint)) or
  substr($mpoint,0,1)ne"/" or length($mpoint)<2 or $mpoint=~m@//@;
#print STDERR "D".(-d $mpoint);
# vvv SUXX: it works only every 2nd time because of fusermount stale etc.
my @L=lstat($mpoint);
#print STDERR "$!..\n" if !@L;
if ((@L or $! !=Errno::ENOTCONN) and !(-d _)) {
  die "$0: cannot create mpoint $mpoint: $!\n" if !mkdir($mpoint);
}

$root_prefix=~s@//+@/@g;
$root_prefix=~s@/*\Z(?!\n)@/@;
$root_prefix=~s@\A/+@/@;
{ my @st=lstat("$root_prefix/.");
  die "$0: cannot stat --root-prefix=: $root_prefix\n" if !@st;
  $all_dev=$st[0];
  #die "all_dev=$all_dev\n";
}

db_connect();

system('fusermount -u -- '.fnq($mpoint).' 2>/dev/null'); # Imp: hide only not-mounted errors, look at /proc/mounts
print STDERR "starting Fuse::main on --mount-point=$mpoint\n" if $DEBUG;
print STDERR "Press Ctrl-<C> to exit (and then umount manually).\n" if $DEBUG;
# vvv Dat: it is also OK to use "Fuse::Demo::my_getattr" instead of
#     \&my_getattr, but now it is more typesafe.
my @ro_ops=(
  getattr=>  \&my_getattr,
  getdir=>   \&my_getdir,
  open=>     \&my_open,
  read=>     \&my_read,
  statfs=>   \&my_statfs,
  readlink=> \&my_readlink,
  flush=>    \&my_flush,
  fsync=>    \&my_fsync,
  release=>  \&my_release,
  getxattr=>    \&my_getxattr,
  listxattr=>   \&my_listxattr,
);
my @write_ops=(
  write=>    \&my_write, # !ro Dat: also needs mknod() (for O_CREAT) and truncate() (for O_TRUNC) and unlink() (for O_CREAT|O_EXCL), otherwise FUSE may return ``Function not implemented''
  mknod=>    \&my_mknod, # !ro
  unlink=>   \&my_unlink, # !ro
  truncate=> \&my_truncate, # !ro
  mknod=>    \&my_mknod, # !ro Dat: without this, we cannot create regular files
  mkdir=>    \&my_mkdir, # !ro
  rmdir=>    \&my_rmdir, # !ro
  symlink=>  \&my_symlink, # !ro
  rename=>   \&my_rename, # !ro
  link=>     \&my_link, # !ro
  chmod=>    \&my_chmod, # !ro
  chown=>    \&my_chown, # !ro
  utime=>    \&my_utime, # !ro
  setxattr=>   \&my_setxattr, # !ro
  removexattr=>\&my_removexattr, # !ro
);

Fuse::main(mountpoint=>$mpoint,
  #mountopts=>'allow_other', # etc., echo user_allow_other >>/etc/fuse.conf
  #mountopts=>'user_xattr', # Dat: not possible to pass user_xattr here...
  #treaded=>0, # Dat: threaded=>1 needs ithreads and precautions
  @ro_ops,
  ($read_only_p ? () : @write_ops),
);
# ^^^ Dat: might die with:
#     fusermount: fuse device not found, try 'modprobe fuse' first
#     could not mount fuse filesystem!

__END__

