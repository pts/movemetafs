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
#
package MMFS;
use Cwd;
use Fuse ':xattr';
use integer;
use strict;
use DBI;
#use DBD::mysql; # Dat: automatic for DBI->connect

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
  my $rv=$sth->execute(@_);
  $sth->finish();
  $rv
}

#** See mysql/mysqld_ername.h
sub ER_DUP_ENTRY() { 1062 }

sub db_transaction($) {
  my($sub)=@_;
  die "already in transaction\n" if db_connect()->{AutoCommit};
  $dbh->begin_work();
  my $ret=eval { $sub->() }; # Imp: wantarray()
  if ($@) {
    $dbh->rollback() if !$dbh->{AutoCommit};
    die $@;
  } else {
    $dbh->commit() if !$dbh->{AutoCommit};
  }
  $ret
}

# -- movemetafs-specific database routines

my $all_fs=config_get('all.fs','F'); # !!
my $all_dev; # st_dev of "$root_prefix/."
die if 0==length($all_fs);

sub verify_tag($) {
  my($tag)=@_;
  die "bad tag\n" if $tag!~/\A[0-9a-zA-Z_\x80-\xFF]{1,255}\Z(?!\n)/;
  verify_utf8($tag);
  undef
}

sub db_insert_tag($) {
  my($tag)=@_;
  verify_tag($tag);
  #my $rv=db_do("INSERT INTO tags (tag,ino,fs) VALUES (?,0,'') ON DUPLICATE KEY UPDATE tag=?", $tag, $tag) };
  # Dat: $rv==1: inserted, $rv==2: updated. Where is this documented?
  eval { db_do("INSERT INTO tags (tag,ino,fs) VALUES (?,0,'')", $tag) };
  die "tag already exists\n" if $@ and $dbh->err==ER_DUP_ENTRY;
  die $@ if $@;
  undef
}

sub db_delete_tag($) {
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

sub db_have_tag($) {
  my($tag)=@_;
  print STDERR "DB_HAVE_TAG($tag)\n";
  # Imp: is COUNT(*) faster?
  my $sth=db_query("SELECT 1 FROM tags WHERE tag=? LIMIT 1",$tag);
  my $ret=($sth->fetchrow_array()) ? 1 : 0;
  print STDERR "DB_HAVE_TAG($tag) = $ret\n";
  $sth->finish();
  $ret
}

#** @return :List(String) tags
sub db_tags() {
  print STDERR "DB_TAGS()\n";
  map { $_->[0] } @{db_query_all(
    "SELECT tag FROM tags GROUP BY tag ORDER BY tag")}
}



#my $sth=db_query("SHOW TABLES");
#my $ar;
#while ($ar=$sth->fetchrow_arrayref()) { print "@$ar.\n" }
#print "qdone\n";
#$sth=db_query("SHOW TABLES");
#while ($ar=$sth->fetchrow_arrayref()) { print "@$ar.\n" }
#print "qdone\n";
#db_insert_tag("vacation");
#db_delete_tag("vacation");

#** @param $_[0] shortname
sub shorten_with_ext_bang($) {
  my $ext=''; $ext=$1 if $_[0]=~s@([.][^.]{1,15})\Z(?!\n)@@;
  die if length($ext)>16;
  substr($_[0],255-length($ext))='';
  $_[0].=$ext;
  undef
}

#** @return :Boolean
sub db_have_other_shortname($$$) {
  my($shortprincipal,$fs,$ino)=@_;
  # vvv Imp: faster than COUNT(*)?
  my $L=db_query_all(
    "SELECT COUNT(*) FROM files WHERE shortprincipal=? AND (ino<>? OR fs<>?)",
    $shortprincipal, $ino,$fs);
  $L->[0][0]
}

#** @return ($shortprincipal,$shortname) :Strings
sub gen_shorts($$$) {
  my($principal,$fs,$ino)=@_;
  my $shortname=$principal;
  $shortname=~s@\A.*/@@s;
  shorten_with_ext_bang($shortname);
  my $shortprincipal=$shortname;
  if ($shortname=~m@\A:[0-9a-f]+:@ or
      db_have_other_shortprincipal($shortprincipal,$fs,$ino)) {
    my $prepend=sprintf(":%x:%s:",$ino,$fs);
    die if length($prepend)>127;
    substr($shortname,0,0)=$prepend; # Dat: not largefile-safe
    shorten_with_ext_bang($shortname);
  }
  ($shortprincipal,$shortname)
}

#** :String. Empty or ends with slash. May start with slash. Doesn't contain
#** a double slash. Empty string means current folder.
#** $root_prefix specifies the real filesystem path to be seen in
#** "$mpoint/root"
my $root_prefix='';

#** @return ($fs,$ino)
sub file_principal_to_fs_ino($) {
  my($principal)=@_;
  my @st;
  die "empty principal\n" if !defined $principal or 0==length($principal);
  die "principal not found\n" unless @st=lstat($root_prefix.$principal);
  die "principal not a file\n" if !-f _;
  die "principal on different filesystem" if $st[0] ne $all_dev;
  ($all_fs,$st[1]) # Imp: better than $all_fs
}

#** Ensures that table files contains $principal. !! Searches by ($fs,$ino).
sub db_ensure_principal($;$$) {
  my($principal,$fs,$ino)=@_;
  db_transaction(sub {
    if (0==$dbh->query_all("SELECT COUNT(*) FROM files WHERE principal=?", $principal)->[0][0]) {
      # Dat: with transactions, this ensures that the same $principal is not inserted twice (really?? !! test it)
      ($fs,$ino)=file_principal_to_fs_ino($principal) if !defined$ino; # Dat: this might die()
      my ($shortprincipal,$shortname)=gen_shorts($principal,$fs,$ino);
      db_do("INSERT INTO files (principal,shortname,shortprincipal,ino,fs) VALUES (?,?,?,?)",
        $principal, $shortname, $shortprincipal, $ino, $fs); # Dat: this shouldn't throw
    }
  });
}

#** Changes files.principal of $real to $real
sub db_rename_principal($) {
  my($fn)=@_;
  my $principal=$fn;
  die "not a mirrored filename\n" if $principal!~s@\A/root/+@@;
  my($fs,$ino)=file_principal_to_fs_ino($principal); # Dat: this might die()
  my $rv=db_do("UPDATE files SET principal=? WHERE ino=? AND fs=?",
    $principal, $ino, $fs); # Dat: might have no effect
  print STDERR "RENAME_PRINCIPAL principal=($principal) ino=$ino fs=($fs) affected=$rv\n" if $DEBUG;
  $rv
}

sub db_add_tag($$) {
  my($fn,$tag)=@_;
  my $principal=$fn;
  die "not a mirrored filename\n" if $principal!~s@\A/root/+@@;
  print STDERR "DB_ADD_TAG principal=($principal) tag=($tag)\n" if $DEBUG;
  my($fs,$ino)=file_principal_to_fs_ino($principal); # Dat: this might die()
  print STDERR "DB_ADD_TAG principal=($principal) tag=($tag) ino=$ino fs=($fs)\n" if $DEBUG;
  
}

#die $dbh->{AutoCommit};
#db_connect()->begin_work();
##die $dbh->{AutoCommit} ? 1 : 0;
#db_connect()->rollback();
# eval { db_query("FOO BAR"); }; die "($@)";

#  principal VARBINARY(32000) NOT NULL,
#  shortname VARBINARY(255) NOT NULL UNIQUE,
#  shortprincipal VARBINARY(255) NOT NULL,
#  ino INTEGER UNSIGNED NOT NULL,
#  fs VARBINARY(127) NOT NULL,


# vvv Imp: verify all die()s, add them here
my %dienerrnos=(
  'bad tag' => -1*Errno::EINVAL,
  'bad UTF-8 string' => -1*Errno::EINVAL,
  'tag not found' => -1*Errno::ENOENT,
  'empty principal' => -1*Errno::EINVAL,
  'principal not a file' => -1*Errno::ENOTSUP,
  'principal not found' => -1*Errno::ENOENT,
  'tag alredy exists' => -1*Errno::EEXIST,
  'tag is in use' => -1*Errno::ENOTEMPTY,
  'principal on different filesystem' => -1*Errno::EREMOTEIO, # Imp: test
  'DBD::mysql::st execute failed' => -1*Errno::EIO, # Dat: by db_query()
  'not a mirrored filename' => -1*Errno::EINVAL,
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
#define __S_IFLNK       0120000 /* Symbolic link.  */
#define __S_IFSOCK      0140000 /* Socket.  */
sub S_IFDIR() { 0040000 } # Directory.
sub S_IFREG() { 0100000 } # Regular file.

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
  print STDERR "GETATTR($fn)\n";
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
  } elsif ($fn eq '/tag') { # Imp: handle /tag/*
  } elsif ($fn=~m@\A/tag/([^/]+)\Z(?!\n)@) { # Dat: ls(!) and zsh(1) echo tag/* needs it
    my $subdir=$1;
    return -1*Errno::ENOENT if !db_have_tag($subdir);
    $mode=($mode&0644)|S_IFDIR;
  } elsif ($fn eq '/root') {
  } elsif (defined($real=sub_to_real($fn))) {
    # Dat: rofs also uses lstat() instead of stat()
    my @L=lstat($real);
    return -1*$! if !@L;
    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=@L;
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
    return ('.','..','tag','root', 0); # $errno
  } elsif ($dir eq '/tag') {
    return ('.','..',db_tags(), 0)
  } elsif ($dir=~m@\A/tag/([^/]+)\Z(?!\n)@) { # Dat: ls(!) and zsh(1) echo tag/* needs it
    return ('.','..',0); # Imp: not empty dir
  } elsif (!defined($real=sub_to_real($dir))) {
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
  return 0
}

sub my_read($$$) {
  my($fn,$size,$offset)=@_;
  my $real;
  my $F;
  #$offset=0 if !defined $offset;
  print STDERR "READ($fn,$size,$offset)\n" if $DEBUG;
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
    return -1*Errno::EPERM
  } elsif (!unlink($real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_rmdir($) {
  my($fn)=@_;
  my $real;
  print STDERR "RMDIR($fn)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/tag/([^/]+)\Z(?!\n)@) {
      my $tag=$1;
      eval { db_delete_tag($tag); };
      return diemsg_to_nerrno();
    }
    return -1*Errno::EPERM
  } elsif (!rmdir($real)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_mkdir($$) {
  my($fn,$mode)=@_;
  my $real;
  # Dat: FUSE calls: GETATTR(), MKDIR(), GETATTR()
  print STDERR "MKDIR($fn,$mode)\n" if $DEBUG;
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/tag/([^/]+)\Z(?!\n)@) {
      my $tag=$1;
      eval { db_insert_tag($tag); };
      return diemsg_to_nerrno();
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
    if ($fn=~m@/tag/([^/]+)/[^/]+\Z(?!\n)@ and defined(sub_to_real($oldfn))) {
      # !! move from "/tag/$tag/$shortprincipal" etc. (automatic?)
      my $tag=$1;
      eval { db_add_tag($oldfn,$tag) };
      return diemsg_to_nerrno()
    }
    return -1*Errno::EPERM
  } elsif (!defined($oldreal=sub_to_real($oldfn))) {
    return -1*Errno::EXDEV
  } elsif (!rename($oldreal,$real)) {
    return -1*$!
  } else {
    eval { db_rename_principal($fn) };
    return diemsg_to_nerrno()
  }
}

sub my_readlink($) {
  my($fn)=@_;
  my $real;
  my $ret;
  print STDERR "READLINK($fn)\n" if $DEBUG;
  # Imp: possibly translate absolute links to relative ones to avoid going up
  #      above the mountpoint
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!defined($ret=readlink($real))) {
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
  print STDERR "STATFS()\n";
  return -1*Errno::ENOANO;
}

sub my_flush($) {
  my($fn)=$_[0];
  print STDERR "FLUSH($fn)\n";
  return 0;
}

sub my_fsync($) {
  my($fn)=$_[0];
  print STDERR "FSYNC($fn)\n";
  return 0;
}

sub my_release($$) {
  my($fn,$flags)=@_;
  print STDERR "RELEASE($fn)\n";
  return 0;
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_getxattr_low($$) {
  my($fn,$attrname)=@_;
  my $real;
  if (!defined($real=sub_to_real($fn))) {
    if ($attrname eq 'user.fakefile') { "1" }
    else { 0 }
  } else {
    if ($attrname eq 'user.realfile') { "1" }
    else { 0 }
  }
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_getxattr($$) {
  my($fn,$attrname)=@_;
  print STDERR "GETXATTR($fn,$attrname)\n" if $DEBUG;
  my_getxattr_low($fn,$attrname)
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_setxattr($$$) {
  my($fn,$attrname,$flags)=@_;
  #my $real;
  print STDERR "SETXATTR($fn,$attrname,$flags)\n" if $DEBUG;
  # Dat: we can use XATTR_CREATE and XATTR_REPLACE from Fuse::
  return -1*Errno::EPERM
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_removexattr($$) {
  my($fn,$attrname)=@_;
  print STDERR "REMOVEXATTR($fn,$attrname)\n" if $DEBUG;
  # vvv Imp: disinguish "0" and 0 (with Scalar::Util?)
  if (my_getxattr_low($fn,$attrname)eq"0") { # Dat: no such attribute
    return -1*Errno::ENOATTR
  } else {
    return -1*Errno::EPERM
  }
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_listxattr($) {
  my($fn)=@_;
  my $real;
  my @attrs;
  print STDERR "LISTXATTR($fn)\n" if $DEBUG;
  # Dat: getfattr(1) `getfattr -d' needs the "user." prefix
  if (!defined($real=sub_to_real($fn))) {
    push @attrs, 'user.fakefile';
  } else {
    push @attrs, 'user.realfile';
  }
  push @attrs, 0; # $errno indicator
  #print STDERR "ATTRS=@attrs\n";
  @attrs
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
    elsif ($ARGV[$I] eq '--version') { print STDERR __PACKAGE__.' $Id: mmfs_fuse.pl,v 1.3 2007-01-04 22:55:01 pts Exp $'."\n"; exit 0 }
    else { die "$0: unknown option: $ARGV[$I]\n" }
  }
  splice @ARGV, 0, $I;
  die "$0: extra args\n" if @ARGV;
}
die "$0: missing --mount-point=\n" if !defined $mpoint or 0==length($mpoint);
die "$0: cannot find mpoint\n" if !defined($mpoint=Cwd::abs_path($mpoint)) or
  substr($mpoint,0,1)ne"/" or length($mpoint)<2 or $mpoint=~m@//@;

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
  # vvv !! why do we get setxattr("f/root/tmp/almaa", "user.realfile", "", 0, ) = -1 EOPNOTSUPP (Operation not supported)
  setxattr=>   \&my_setxattr, # !ro
  # vvv !! why do we get setxattr("f/root/tmp/almaa", "user.realfile", "", 0, ) = -1 EOPNOTSUPP (Operation not supported)
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
