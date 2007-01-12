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
# Dat: FUSE is smart enough so GETDIR gets / instead of $config{'mount.point'}, so we
#      can avoid the deadlock. But we nevertheless hide $config{'mount.point'} inside
#      $config{'mount.point'}.
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
BEGIN { $VERSION='0.05' }

# --- Configuration functions

my @config_argv;
my %config;
$config{'verbose.level'}=1;
my $config_fn='movemetafs.conf'; # !! change in the command line

#** Only keys listed in %config_default are allowed in the config file, other
#** keys are ignored (warning if read from the config file, error if specified
#** in the command line).
#**   If the default value is a scalar ref (e.g. \1), the key is mandatory.
#** Dat: no `-' or `_' here, only `.'
my %config_default=(
  'db.dsn'=>\1,
  'db.username'=>'root',
  'db.auth'=>'',
  'db.onconnect.1'=>undef,
  'db.onconnect.2'=>undef,
  'db.onconnect.3'=>undef,
  'db.onconnect.4'=>undef,
  'db.onconnect.5'=>undef,
  'db.onconnect.6'=>undef,
  'db.onconnect.7'=>undef,
  'db.onconnect.8'=>undef,
  'db.onconnect.9'=>undef,
  'default.fs'=>'F',
  'read.only.p'=>0, # Imp: verify boolean
  'enable.purgeallmeta.p'=>0, # Imp: verify boolean
  'verbose.level'=>1,
  #** Absolute dir. Starts with slash. Doesn't end with slash. Doesn't contain
  #** a double slash. Isn't "/".
  'mount.point'=>"$ENV{HOME}/mmfs", # \1,
  #** :String. Empty or ends with slash. May start with slash. Doesn't contain
  #** a double slash. Empty string means current folder.
  #** $root_prefix specifies the real filesystem path to be seen in
  #** "$config{'mount.point'}/root"
  'root.prefix'=>'/',
);

#** Processes a command-line option
#** Dat: this is specific to movemetafs
#** @return :Boolean processed?
sub config_process_option($) {
  my($opt)=@_;
  if (0) {}
  elsif ($opt eq '--verbose') { $config{'verbose.level'}++ }
  elsif ($opt eq '--quiet'  ) { $config{'verbose.level'}-- }
  elsif ($opt eq '--version') {
    print STDERR "movemetafs v$VERSION".' $Id: mmfs_fuse.pl,v 1.22 2007-01-12 03:00:18 pts Exp $'."\n";
    print STDERR "by Pe'ter Szabo' since early January 2007\n";
    print STDERR "The license is GNU GPL >=2.0. It comes without warranty. USE AT YOUR OWN RISK!\n";
    exit 0
  }
  elsif ($opt eq '--help') { die "$0: no --help, see README.txt\n" }
  elsif ($opt eq '--test-db') { mydb_test(); exit }
  elsif ($opt=~/--config-file=(.*)/s) { } # Dat: too late to set $config_fn=$1
  else { return 0 }
  1
}

sub config_process_argv() {
  my $I;
  if (!@config_argv) {
    for ($I=0;$I<@ARGV;$I++) {
      if ($ARGV[$I] eq'-' or substr($ARGV[$I],0,1)ne'-') { last }
      elsif ($ARGV[$I] eq '--') { $I++; last }
      push @config_argv, $ARGV[$I];
    }
    splice @ARGV, 0, $I, '--';
    push @config_argv, '--'; # Dat: to make config_process_argv() idempotent
  }
  for my $arg (@config_argv) {
    if ($arg eq '--') { last }
    elsif (config_process_option($arg)) {}
    elsif ($arg=~/-+([^=]+)=(.*)/s) { config_set($1,$2) }
    else { die "$0: unknown option: $arg\n" }
  }
  undef
}

#** @return processed key
sub config_set($$;$) {
  my($key,$val,$warn_p)=@_;
  $key=~y@-_@..@;
  #print STDERR "\$config{'$key'}='$val';\n";
  if (exists $config_default{$key}) {
    $config{$key}=$val;
  } elsif ($warn_p) {
    print STDERR "$0: warning: unknown key $key in config file $config_fn\n";
    $key='';
  } else { die "$0: unknown config key: $key\n" }
  $key
}

#** Dat: Good for config files ad `getfattr -d -e text' dumps.
sub decode_cq($) {
  my $S=$_[0];
  $S=~s@\\([0-3]?[0-7]?[0-7])|\\(.)@
    defined $1 ? chr(oct$1) :
    $2 eq 'n' ? "\n" : $2 eq 't' ? "\t" : $2 eq 'f' ? "\f" :
    $2 eq 'b' ? "\010" : $2 eq 'a' ? "\007" : $2 eq 'e' ? "\033" : # Dat: Perl
    $2 eq 'v' ? "\013" : $2 eq 'r' ? "\r" : $2 # Dat: Perl doesn't have \v
    @ges; # Imp: more, including \<newline>
  $S
}

sub config_reread() {
  if (!@config_argv) {
    # Dat: see this above: $config_fn='movemetafs.conf';
    # Imp: find config file near $0
    for (my $I=0;$I<@ARGV;$I++) {
      if ($ARGV[$I] eq'-' or substr($ARGV[$I],0,1)ne'-') { last }
      elsif ($ARGV[$I] eq '--') { $I++; last }
      elsif ($ARGV[$I]=~/--config-file=(.*)/s) { $config_fn=$1 }
    }
  }
  %config=map { 'SCALAR' eq ref $config_default{$_} ? () :
    ($_ => $config_default{$_}) } keys %config_default;
  my %config_file_keys;
  my $line;
  die "$0: cannot open config file $config_fn: $!\n" unless open my($F), '<', $config_fn;
  while (defined($line=<$F>)) {
    next if $line!~/\S/ or $line=~/\A\s*\#/;
    my($key,$val);
    die "syntax error in config file: $config_fn, line $.\n" unless
      $line=~s@\A\s*([^\s:=]+)\s*[:=]\s*@@;
    $key=$1;
    $line=~s@\s+\Z(?!\n)@@;
    if ($line=~m@\A"((?:[^\\"]+|\\.)*)"(?!\n)@s) {
      $val=decode_cq($1);
    } else {
      $val=$line;
    }
    die "duplicate key $key in config file $config_fn, line $.\n" if
      $config_file_keys{$key};
    my $keypp=config_set($key, $val, 1);
    $config_file_keys{$keypp}=1 if defined $keypp;
  }
  die if !close($F);
  config_process_argv();
  for my $key (sort keys %config_default) {
    die "$0: missing mandatory config key $key, see README.txt\n" if
      !defined $config{$key} and 'SCALAR' eq ref $config_default{$key};
  }
  undef
}

sub config_get($;$) {
  my($key,$default)=@_;
  config_reread() if !%config;
  defined $config{$key} ? $config{$key} : $default
}

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
  my $ret=syscall(SYS_mknod(), $fn, $mode, $rdev); # Imp: 64-bit
  (!defined $ret or $ret<0) ? undef : $ret==0 ? "0 but true" : $ret
}

#** Dat: Linux-specific
sub our_setxattr($$$;$) {
  my($fn,$name,$value,$flags)=@_;
  require 'syscall.ph';
  my $ret=syscall(&SYS_setxattr, $fn, $name, $value, length($value),
    ($flags or 0));
  (!defined $ret or $ret<0) ? undef : $ret==0 ? "0 but true" : $ret
}

sub verify_utf8($) {
  my($S)=@_;
  die "bad UTF-8 string\n" if $S!~/\A(?:[\000-\177]+|[\xC0-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF7][\x80-\xBF]{3})*\Z(?!\n)/;
  undef
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

my @db_on_die_rollback;

#** @param $maybe_p proceed if already inside a transaction
sub db_transaction($;$) {
  my($sub,$maybe_p)=@_;
  my $ret;
  if (!db_connect()->{AutoCommit}) {
    die "already in transaction\n" if !$maybe_p;
    $ret=$sub->();
  } else {
    $dbh->begin_work();
    @db_on_die_rollback=();
    $ret=eval { $sub->() }; # Imp: wantarray()
    if ($@) {
      my $err=$@;
      if (!$dbh->{AutoCommit}) {
        $dbh->rollback();
        for my $sub (@db_on_die_rollback) { $sub->() }
      }
      die $err;
    } else {
      @db_on_die_rollback=();
      $dbh->commit() if !$dbh->{AutoCommit};
    }
  }
  $ret
}

# -- movemetafs-specific database routines (mydb_*())

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

sub mydb_test($) {
  db_connect();
  print STDERR "Database connect OK.\n";
  # vvv !! keep this up-to-date
  db_do("SELECT principal,shortname, shortprincipal,ino,fs,descr FROM files WHERE 1=2 LIMIT 1");
  db_do("SELECT ino,fs,tagtxt FROM taggings WHERE 1=2 LIMIT 1");
  db_do("SELECT ino,fs,tag FROM tags WHERE 1=2 LIMIT 1");
  db_do("SELECT fs,mpoint,dev,root_ino,top_ino FROM fss WHERE 1=2 LIMIT 1");
  # vvv Dat: test write access
  db_do("UPDATE taggings SET ino=ino WHERE 1=2 LIMIT 1");
  db_do("DELETE FROM taggings WHERE 1=2 LIMIT 1");
  db_transaction(sub {
    db_do("INSERT INTO tags (ino,fs,tag) VALUES (1,2,3)");
    $dbh->rollback();
  });
  print STDERR "Tables OK.\n";
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
  print STDERR "DB_HAVE_TAG($tag)\n" if $config{'verbose.level'};
  # Imp: is COUNT(*) faster?
  my $sth=db_query("SELECT 1 FROM tags WHERE tag=? LIMIT 1",$tag);
  my $ret=($sth->fetchrow_array()) ? 1 : 0;
  print STDERR "DB_HAVE_TAG($tag) = $ret\n" if $config{'verbose.level'};
  $sth->finish();
  $ret
}

#** @return :List(String) tags
sub mydb_list_tags() {
  print STDERR "DB_LIST_TAGS()\n" if $config{'verbose.level'};
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
  print STDERR "SEARCHING FOR SIMILARS to shortprincipal=($shortprincipal) fs=($fs) ino=$ino.\n" if $config{'verbose.level'};
  my $sth=db_query("SELECT fs, ino, shortname FROM files WHERE shortprincipal=? AND NOT (ino=? AND fs=?)",
    $shortprincipal, $ino, $fs);
  my($fs1,$ino1,$shortname0);
  my @sql_updates;
  while (($fs1,$ino1,$shortname0)=$sth->fetchrow_array()) {
    my $shortname1=$shortprincipal;
    $use_longer_p=1;
    print STDERR "SIMILAR SHORTNAME fs=($fs1) ino=$ino1 $shortname1.\n" if $config{'verbose.level'};
    my $prepend1=sprintf(":%x:%s:",$ino1,$fs1);
    ##print STDERR "prepend1=$prepend1\n";
    die if length($prepend1)>127;
    substr($shortname1,0,0)=$prepend1; # Dat: not largefile-safe
    shorten_with_ext_bang($shortname1);
    print STDERR "SIMILAR SHORTNAME CHANGING TO $shortname1.\n" if $config{'verbose.level'};
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

#** Also verify_principal().
sub verify_localname($) {
  my($localname)=@_;
  die "empty localname\n" if !defined $localname or 0==length($localname);
  die "bad slashes in localname: $localname\n" if
    substr($localname,0,1)eq'/' or
    substr($localname,-1)eq'/' or index($localname,'//')>=0;
}

#** Cache of the table `fss'.
#** Test with `defined' (not `exists') because of @db_on_die_rollback.
my %dev_to_fs;

sub mydb_fill_dev_to_fs() {
  print STDERR "DB_FILL_DEV_TO_FS\n" if $config{'verbose.level'};
  my $sth=db_query("SELECT dev, fs FROM fss");
  %dev_to_fs=();
  while (my($dev,$fs)=$sth->fetchrow_array()) {
    $dev_to_fs{$dev}=$fs
  }
}

#** Dat: separate subroutine to have as few `my' as possible
sub mydb_rollback_dev_to_fs($) {
  return if $dbh->{AutoCommit};
  my($dev)=@_;
  my $oldfs=$dev_to_fs{$dev};
  push @db_on_die_rollback, sub { $dev_to_fs{$dev}=$oldfs; undef };
}

#** Dat: needs transaction
#** Possibly autoassigns a new fs.
#** @return $fs (existing or generated)
sub mydb_insert_fs($;$) {
  my($dev,$fs)=@_;
  print STDERR "DB_INSERT_FS dev=$dev\n" if $config{'verbose.level'};
  db_transaction(sub {
    my $L=db_query_all("SELECT fs FROM fss WHERE dev=? LIMIT 1", $dev);
    if (@$L) { # Dat: somebody has inserted it
      $fs=$L->[0][0];
    } else {
      $fs='' if !defined $fs;
      if (0==length($fs)) {
        if (!@{db_query_all("SELECT 1 FROM fss LIMIT 1")}) {
          $fs=$config{'default.fs'}; # Dat: can be empty
        }
      }
      db_do("DELETE FROM fss WHERE fs=''") if 0==length($fs);
      # vvv Imp: robust, what if already inserted?
      db_do("INSERT INTO fss (fs,dev) VALUES (?,?)", $fs, $dev);
      if (0==length($fs)) {
        $fs=$dbh->{'mysql_insertid'};
        die "bad insertid: $fs.\n" if !defined($fs) or $fs<1;
        $fs=".$fs";
        db_do("UPDATE fss SET fs=? WHERE fs=''", $fs);
      }
    }
  },1);
  print STDERR "DB_INSERT_FS dev=$dev fs=($fs)\n" if $config{'verbose.level'};
  mydb_rollback_dev_to_fs($dev); # Dat: remove from cache on rollback
  return $dev_to_fs{$dev}=$fs
}

#** Dat: change this to have multiple filesystem support
#** @return ($fs,$ino)
sub mydb_file_localname_to_fs_ino($;$$) {
  my($localname,$allow_nonfile_p,$allow_unknown_fs_p)=@_;
  die if db_connect()->{'AutoCommit'} and !$allow_unknown_fs_p;
  # ^^^ Dat: needs a transaction if $fs must be known
  my($dev,$ino);
  die "localname not found\n" unless
    ($dev,$ino)=lstat($config{'root.prefix'}.$localname);
  die "localname not a file\n" if !$allow_nonfile_p and !-f _;
  my $dir_p=(-d _);
  my $fs=$dev_to_fs{$dev};
  $fs=mydb_insert_fs($dev) if !defined$fs and !$allow_unknown_fs_p;
  #die "GOT fs=($fs)\n";
  ($fs,$ino,$dir_p)
}

#** Dat: change this to have multiple filesystem support
sub mydb_file_st_to_fs_ino($$;$) {
  my($st_dev,$st_ino,$allow_unknown_fs_p)=@_;
  die if db_connect()->{'AutoCommit'}; # Dat: needs transaction
  my $fs=$dev_to_fs{$st_dev};
  if (!defined$fs) {
    return (undef,undef) if $allow_unknown_fs_p;
    $fs=mydb_insert_fs($st_dev);
    die if !defined $fs;
  }
  #print STDERR "DB_FILE_ST_TO_FS_INO fs=($fs) st_dev=($st_dev)\n" if $config{'verbose.level'};
  ($fs,$st_ino)
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
    ($fs,$ino)=mydb_file_localname_to_fs_ino($localname) if !defined$ino; # Dat: this might die()
    mydb_insert_fs_ino_principal($fs,$ino,$localname);
  },1);
}

#** Deletes a row from tables `files' if the row doesn't contain useful
#** information.
#** @in No tags are associated with the file, tags don't have to be checked.
sub mydb_delete_from_files_if_no_info($$) {
  my($fs,$ino)=@_;
  print STDERR "DB_DELETE ino=$ino fs=($fs)\n" if $config{'verbose.level'};
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

#** Dat: also changes files.principal.
#** Dat: if $oldfn eq $fn, this is equivalent to moving the file to
#**      `meta/adm/fixprincipal'.
sub mydb_rename_fn_to($) {
  my($fn)=@_;
  print STDERR "DB_RENAME_FN to fn=($fn)\n" if $config{'verbose.level'};

  # vvv Dat: can be anything, only the new name matters
  #my $oldlocalname=$oldfn;
  #die "not a mirrored filename\n" if $oldlocalname!~s@\A/root/+@@;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@;

  db_transaction(sub {
    #print STDERR "AAA\n";
    # vvv Dat: $allow_nonfile_p, because it might be a folder
    my($fs,$ino,$dir_p)=eval { mydb_file_localname_to_fs_ino($localname,1,1) }; # Dat: this might die()
    #print STDERR "BBB($@)\n";
    return if $@; # Dat: maybe 'localname not a file' -- must exist, we've just renamed (!! Imp: avoid race condition)
    #print STDERR "CCC\n";
    my $L;
    my $oldprincipal_calc;
    if (!defined $fs) {
      # Dat: we don't know anything about the target filesystem yet, but the
      #      rename(2) has already succeeded. This means `files' cannot contain
      #      $localname, so it doesn't have to be changed, so we don't have to
      #      do anything.
      #db_transaction(sub {
      #  ($fs,$ino)=mydb_file_localname_to_fs_ino($localname);
      #  mydb_rename_fn_low($oldshortprincipal, $shortprincipal, $localname, $ino, $fs);
      #});
      print STDERR "DB_RENAME_FN unknown fs localname=($localname)\n" if $config{'verbose.level'};
      $dir_p=0;
    } elsif (!@{$L=db_query_all("SELECT principal FROM files WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) {
      if (@{db_query_all("SELECT 1 FROM tags WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) { # maybe we have it in `tags'
        print STDERR "DB_RENAME_FN reinsert tagged\n" if $config{'verbose.level'};
        mydb_ensure_fs_ino_name($fs,$ino,$localname);
      }
      # Dat: now we need an $oldfn -> $oldprincipal_calc for proper renames
      #      renames. Thus meta/adm/fixprincipal cannot work
      $dir_p=0;
    } else {
      $oldprincipal_calc=$L->[0][0];
      my $oldshortprincipal=$oldprincipal_calc;
      $oldshortprincipal=~s@\A.*/@@s;
      shorten_with_ext_bang($oldshortprincipal);

      my $shortprincipal=$localname;
      $shortprincipal=~s@\A.*/@@s;
      shorten_with_ext_bang($shortprincipal);
      mydb_rename_fn_low(  $oldshortprincipal, $shortprincipal, $localname, $ino, $fs)
    }
    if ($dir_p or $oldprincipal_calc ne $localname) {
      my $principal_likeq=$oldprincipal_calc;
      $principal_likeq=~s@([\%_\\])@\\$1@g; # Imp: mysql_likeq()
      # vvv Dat: no proper escape for sprintf() debug message below
      #print STDERR sprintf("DB_RENAME_FN UPDATE files SET principal=CONCAT('%s',SUBSTRING(BINARY principal FROM %d)) WHERE principal LIKE '%s'\n",
      #  $localname, 1+length($oldprincipal_calc), "$principal_likeq/%");
      # vvv Dat: BINARY doesn't seem to ruin our character encoding
      my $rv=db_do("UPDATE files SET principal=CONCAT(?,SUBSTRING(BINARY principal FROM ?)) WHERE principal LIKE ?",
        $localname, 1+length($oldprincipal_calc), "$principal_likeq/%");
      print STDERR "DB_RENAME_FN subdir contents rv=$rv\n" if $config{'verbose.level'};
    }
  },1);
}

#** Callable even if ($ino,$fs) is not known in the metadata store.
#** Must be called in a transaction.
sub mydb_rename_fn_low($$$$$) {
  my($oldshortprincipal, $shortprincipal, $principal, $ino, $fs)=@_;
  my($shortprincipal1,$shortname1);
  my $rv;
  if ($oldshortprincipal eq $shortprincipal) { # Dat: shortcut: last filename component doesn't change
    print STDERR "DB_RENAME_FN QUICK TO principal=($principal) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
    $rv=db_do("UPDATE files SET principal=? WHERE ino=? AND fs=?",
      $principal, $ino, $fs); # Dat: might have no effect
    print STDERR "DB_RENAME_FN QUICK TO principal=($principal) ino=$ino fs=($fs) affected=$rv\n" if $config{'verbose.level'};
  } else {
    print STDERR "DB_RENAME_FN TO principal=($principal) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
    ($shortprincipal1,$shortname1)=mydb_gen_shorts($principal,$fs,$ino); # Dat: this modifies the db and it might die()
    $rv=db_do("UPDATE files SET principal=?, shortprincipal=?, shortname=? WHERE ino=? AND fs=?",
      $principal, $shortprincipal1, $shortname1, $ino, $fs); # Dat: might have no effect
    print STDERR "DB_RENAME_FN TO principal=($principal) shortprincipal=($shortprincipal1) shortname=($shortname1) ino=$ino fs=($fs) affected=$rv\n" if $config{'verbose.level'};
  }
  # vvv Dat: caller makes sure
  #if ($rv==0 and @{db_query_all("SELECT 1 FROM tags WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) { # maybe we have it in `tags'
  #  print STDERR "DB_RENAME_FN insert\n" if $config{'verbose.level'};
  #  ($shortprincipal1,$shortname1)=mydb_gen_shorts($principal,$fs,$ino) if
  #    !defined $shortprincipal1;
  #  # vvv Dat: similar to mydb_insert_fs_ino_principal()
  #  db_do("INSERT INTO files (principal,shortname,shortprincipal,ino,fs) VALUES (?,?,?,?,?)",
  #    $principal, $shortname1, $shortprincipal1, $ino, $fs); # Dat: this shouldn't die()
  #}
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
#**   mount.point=)
#** @return :String localname (principal for `tag/.../...') or undef
sub mydb_fn_to_localname($) {
  my($fn)=@_;
  return $fn if $fn=~s@\A/root/+@@;
  my $shortname=spec_symlink_get_shortname($fn);
  return undef if !defined $shortname;
  my $L=db_query_all("SELECT principal FROM files WHERE shortname=?",
    $shortname);
  print STDERR "DB_FN_TO_LOCALNAME shortname=($shortname) got=$L (@$L).\n" if $config{'verbose.level'};
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
    print STDERR "DB_OP_TAG localname=($localname) tag=($tag)\n" if $config{'verbose.level'};
    # Imp: implement file_shortname_to_fs_ino() in addition to
    #      mydb_file_localname_to_fs_ino() to avoid extra database access
    my($fs,$ino)=mydb_file_localname_to_fs_ino($localname); # Dat: this might die()
    print STDERR "DB_OP_TAG localname=($localname) tag=($tag) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
    mydb_ensure_fs_ino_name($fs,$ino,$localname);
    # vvv Dat: different when row already present
    # vvv Dat: `ON DUPLICATE KEY UPDATE' is better than `REPLACE', because
    #     REPLACE deletes 1st
    # vvv Dat: `ON DUPLICATE KEY UPDATE' is better tgen `INSERT ... IGNORE',
    #     because `INSER ... IGNORE' ignores other errors, too
    my $rv=db_do("INSERT INTO tags (ino, fs, tag) VALUES (?,?,?) ON DUPLICATE KEY UPDATE tag=tag",
      $ino, $fs, $tag);
    mydb_update_taggings_for($fs,$ino) if $rv==1; # Dat: $rv==2: updated, $rv==1: inserted
    print STDERR "DB_OP_TAG localname=($localname) tag=($tag) ino=$ino fs=($fs) rv=$rv\n" if $config{'verbose.level'};
  });
}


sub mydb_op_untag($$) {
  my($fn,$tag)=@_;
  die if !defined $tag;
  db_transaction(sub { # Imp: is it faster without a transaction?
    my $localname=mydb_fn_to_localname($fn);
    die "not pointing to a mirrored filename\n" if !defined$localname;
    print STDERR "DB_OP_UNTAG localname=($localname) tag=($tag)\n" if $config{'verbose.level'};
    my($fs,$ino)=mydb_file_localname_to_fs_ino($localname,1,0); # Dat: this might die()
    print STDERR "DB_OP_UNTAG localname=($localname) tag=($tag) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
    my $rv=($tag eq ':all') ?
      db_do("DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs) :
      db_do("DELETE FROM tags WHERE ino=? AND fs=? AND tag=?", $ino, $fs, $tag);
    print STDERR "DB_OP_UNTAG localname=($localname) tag=($tag) ino=$ino fs=($fs) rv=$rv\n" if $config{'verbose.level'};
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
  print STDERR "DB_OP_UNTAG_SHORTNAME shortname=($shortname) tag=($tag)\n" if $config{'verbose.level'};
  db_transaction(sub { # Imp: is it faster without a transaction?
    my $R=db_query_all("SELECT fs, ino FROM files WHERE shortname=? LIMIT 1", $shortname);
    if (@$R) {
      my($fs,$ino)=@{$R->[0]};
      print STDERR "DB_OP_UNTAG_SHORTNAME shortname=($shortname) tag=($tag) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
      my $rv=($tag eq ':all') ?
        db_do("DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs) :
        db_do("DELETE FROM tags WHERE ino=? AND fs=? AND tag=?", $ino, $fs, $tag);
      print STDERR "DB_OP_UNTAG_SHORTNAME shortname=($shortname) tag=($tag) ino=$ino fs=($fs) rv=$rv\n" if $config{'verbose.level'};
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
  print STDERR "DB_REPAIR_TAGGINGS\n" if $config{'verbose.level'};
  db_transaction(sub {
    db_do("DELETE FROM taggings WHERE NOT EXISTS (SELECT * FROM tags WHERE ino=taggings.ino AND fs=taggings.fs)");
    db_do("SET SESSION group_concat_max_len = $db_big_31bit");
    # vvv Dat: this is quite fast on 10000 rows
    # vvv Dat: good, doesn't insert empty `tags'
    # !! this makes mysqld crash because of huge group_concat_max_len
    my $rv=db_do("INSERT INTO taggings (fs, ino, tagtxt)
      SELECT fs, ino, $mydb_concat_tags_sqlpart FROM tags
      WHERE fs<>'' GROUP BY ino, fs
      ON DUPLICATE KEY UPDATE tagtxt=VALUES(tagtxt)");
    print STDERR "DB_REPAIR_TAGGINGS affected=$rv\n" if $config{'verbose.level'};
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
  print STDERR "DB_UPDATE_TAGGINGS ino=$ino fs=($fs)\n" if $config{'verbose.level'};
  db_transaction(sub {
    my $rv="delete";
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
    print STDERR "DB_UPDATE_TAGGINGS affected=$rv\n" if $config{'verbose.level'};
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
    print STDERR "DB_RENAME_TAG oldtag=($oldtag) newtag=($newtag) affected=($rv)\n" if $config{'verbose.level'};
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
  print STDERR "DB_FIND_TAGGED_SHORTNAMES$in_boolean_mode qsq=($qsq)\n" if $config{'verbose.level'};
  my $ret=db_query_all(
    "SELECT shortname FROM taggings, files WHERE MATCH (tagtxt) AGAINST (?$in_boolean_mode) AND taggings.ino=files.ino AND taggings.fs=files.fs",
    $qsq);
  for my $shortname (@$ret) { $shortname=$shortname->[0] }
  # vvv Dat: search results of 8000 files takes up to 0.3s to transfer -- slow?
  print STDERR "DB_FIND_TAGGED_SHORTNAMES found ".scalar(@$ret)." files\n" if $config{'verbose.level'};
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
  my($fs,$ino)=mydb_file_localname_to_fs_ino($localname,0,1); # Dat: this might die()
  return () if !defined $fs;
  map { $_->[0] } @{db_query_all("SELECT tag FROM tags WHERE ino=? AND fs=? ORDER BY tag",
    $ino, $fs)}
}  

#** @return :String or undef (if file is not tagged)
sub mydb_file_get_descr($) {
  my($fn)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  my($fs,$ino)=mydb_file_localname_to_fs_ino($localname,0,1); # Dat: this might die()
  return undef if !defined $fs;
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
  print STDERR "DB_FILE_SET_DESCR localname=($localname) descr=($descr)\n" if $config{'verbose.level'};
  db_transaction(sub {
    my($fs,$ino)=mydb_file_localname_to_fs_ino($localname); # Dat: this might die()
    mydb_ensure_fs_ino_name($fs,$ino,$localname);
    # vvv Dat: we could do this with `WHERE fs=? AND ino=?'
    my $rv=db_do("UPDATE files SET descr=? WHERE ino=? AND fs=?", $descr, $ino, $fs);
    mydb_delete_from_files_if_no_info_and_tags($fs,$ino) if $rv and 0==length($descr);
  });
}

#** @param $setmode 'set', 'tag', 'untag' or 'modify'
#** @return :String or undef (if file is not tagged)
sub mydb_file_set_tagtxt($$$) {
  my($fn,$tagtxt,$setmode)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@; # Dat: no need for doing this on symlinks
  print STDERR "DB_FILE_SET_TAGTXT localname=($localname) tagtxt=($tagtxt) setmode=($setmode)\n" if $config{'verbose.level'};
  if ($setmode eq 'modify') {
    if ($tagtxt!~m@\A\s*-:all\s*\Z(?!\n)@) {
      my @tags_to_tag;
      my @tags_to_untag;
      while ($tagtxt=~m@(\S+)@g) {
        my $tag=$1;
        if ($tag=~s@\A-@@) { push @tags_to_untag, $tag }
        else { push @tags_to_tag, $tag }
        verify_tag($tag)
      }
      # vvv Imp: together in a transaction
      # vvv Dat: run 'tag' first to avoid early DB_DELETE on 'untag'
      mydb_file_set_tags_low($fn,$localname,\@tags_to_tag,'tag');
      mydb_file_set_tags_low($fn,$localname,\@tags_to_untag,'untag');
    } else { mydb_op_untag($fn,':all') }
  } else {
    my @tags;
    while ($tagtxt=~m@(\S+)@g) { push @tags, $1; verify_tag($tags[-1]) }
    mydb_file_set_tags_low($fn,$localname,\@tags,$setmode);
  }
}

sub mydb_file_set_tags_low($$$$) {
  my($fn,$localname,$tags,$setmode)=@_;
  return if !@$tags and $setmode ne 'set';
  db_transaction(sub {
    print STDERR "DB_FILE_SET_TAGTXT_LOW localname=($localname) tags=(@$tags) setmode=($setmode)\n" if $config{'verbose.level'};
    # vvv Dat: similar to mydb_file_get_tags()
    my($fs,$ino)=mydb_file_localname_to_fs_ino($localname); # Dat: this might die()
    # vvv Dat: works even if `fs--ino' is missing from `files'
    my @old_tags=map { $_->[0] } @{db_query_all("SELECT tag FROM tags WHERE ino=? AND fs=? ORDER BY tag",
      $ino, $fs)};
    if ($setmode ne 'set' or join(' ', sort@$tags) ne join(' ', sort@old_tags)) {
      # Imp: DELETE and INSERT only the difference
      if (@$tags) {
        # Dat: no problem if duplicates in @$tags
        # Imp: optimize, remove duplicates
        { my %all_tags;
          # vvv Imp: don't cache statement, and use subset of @$tags
          for my $row (@{db_query_all("SELECT tag FROM tags WHERE ino=0 AND fs=''")}) {
            $all_tags{$row->[0]}=1
          }
          for my $tag (@$tags) { die "unknown tag: $tag\n" if !defined $all_tags{$tag} }
        }
        # Imp: implement file_shortname_to_fs_ino() in addition to
        #      mydb_file_localname_to_fs_ino() to avoid extra database access
        print STDERR "DB_FILE_SET_TAGTXT localname=($localname) tags=(@$tags) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
        mydb_ensure_fs_ino_name($fs,$ino,$localname);
        ## vvv Dat: different when row already present
        if ($setmode eq 'untag') {
          for my $tag (@$tags) { # Imp: faster (cannot do w/o multiple INSERTs :-(
            db_do("DELETE FROM tags WHERE ino=? AND fs=? AND tag=?",
              $ino, $fs, $tag);
            #$had_change_p=1 if $rv==1; # Dat: $rv==2: updated, $rv==1: inserted
          }
          # vvv Dat: `_and_tags' is very important
          mydb_delete_from_files_if_no_info_and_tags($fs,$ino);
        } else {
          db_do("DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs) if
            $setmode eq 'set';
          for my $tag (@$tags) { # Imp: faster (cannot do w/o multiple INSERTs :-(
            db_do("INSERT INTO tags (ino, fs, tag) VALUES (?,?,?) ON DUPLICATE KEY UPDATE tag=tag",
              $ino, $fs, $tag);
            #$had_change_p=1 if $rv==1; # Dat: $rv==2: updated, $rv==1: inserted
          }
        }
        mydb_update_taggings_for($fs,$ino); # Dat: a if $had_change_p;
      } else {
        mydb_op_untag($fn,':all') if $setmode eq 'set';
      }
    } else {
      print STDERR "DB_FILE_SET_TAGTXT localname=($localname) tags=(@$tags) unchanged\n" if $config{'verbose.level'};
    }
  },1);
}

#** Is unlink OK if $fn has multiple hard links?
sub mydb_may_unlink_multi($) {
  my($fn)=@_;
  !mydb_fn_is_principal($fn)
}

#** Unlinks the last hard link of the file from the database.
#** @param $fn is not ignored if $st_dev and $st_ino are specified
sub mydb_unlink_last($;$$$$) {
  my($fn,$st_dev,$st_ino,$by_principal_p)=@_;
  my $localname=$fn;
  die "not a mirrored filename\n" if $localname!~s@\A/root/+@@ and
    !defined $st_ino;
  my $extrastr=defined$st_ino ? " st_dev=$st_dev st_ino=$st_ino" : "";
  print STDERR "DB_UNLINK_LAST @{[$by_principal_p?qq(principal):qq(localname)]}=($localname)$extrastr\n" if $config{'verbose.level'};
  db_transaction(sub {
    # vvv Dat: too late to lstat(2), already deleted.
    my($fs,$ino,$L);
    if (!$by_principal_p and defined$st_ino) {
      ($fs,$ino)=mydb_file_st_to_fs_ino($st_dev,$st_ino,1); # Dat: this might die()
      print STDERR "DB_UNLINK_LAST unknown fs\n" if $config{'verbose.level'} and
        !defined $fs;
    } elsif (!$by_principal_p) {
      ($fs,$ino)=mydb_file_localname_to_fs_ino($localname,1,1);
    } elsif (!@{$L=db_query_all("SELECT fs, ino FROM files WHERE principal=?", $localname)}) {
      print STDERR "DB_UNLINK_LAST principal-not-in-files\n";
    } else {
      ($fs,$ino)=@{$L->[0]};
    }
    if (!defined $fs) {
    } elsif (@{db_query_all("SELECT 1 FROM files WHERE ino=? AND fs=? LIMIT 1", $ino, $fs)}) {
      print STDERR "DB_UNLINK_LAST localname=($localname) ino=$ino fs=($fs)\n" if $config{'verbose.level'};
      #db_transaction(sub {
        my $rv1=db_do(   "DELETE FROM files WHERE ino=? AND fs=?", $ino, $fs);
        my $rv2=db_do(    "DELETE FROM tags WHERE ino=? AND fs=?", $ino, $fs);
        my $rv3=db_do("DELETE FROM taggings WHERE ino=? AND fs=?", $ino, $fs);
        print STDERR "DB_UNLINK_LAST localname=($localname) ino=$ino fs=($fs) rv=$rv1+$rv2+$rv3\n" if $config{'verbose.level'};
      #});
    } else {
      print STDERR "DB_UNLINK_LAST localname=($localname) ino=$ino fs=($fs) not-in-files\n" if $config{'verbose.level'};
    }
  });
}

#** Converts empty string to empty string, newline to ="\012" etc,
#** similar to `getfattr -e text'.
sub getfattr_eqvalq($) {
  return '' if 0==length($_[0]);
  my($S)=@_;
  # vvv Dat: wastes: converts a 2-byte UTF-8 character to 8 bytes...
  $S=~s@([^ -~])@ sprintf"\\%03o", ord$1 @ge;
  qq(="$S")
}

#** Produces a dump similar to `getfattr -R -d -e text'
#** Dat: doesn't touch the filesystem, gets everything from the database.
#** @param $prefix '' or "$principalprefix/"
#** @param $F IO-handle to write (but don't close)
sub mydb_attr_dump($$) {
  my($prefix,$F)=@_;
  $prefix=~s@/+\Z(?!\n)@@;
  $prefix=~s@//+@/@g;
  $prefix=~s@\A/+@@;
  print STDERR "DB_ATTR_DUMP prefix=($prefix)\n" if $config{'verbose.level'};
  #print $F "hello, world\n";
  db_do("SET SESSION group_concat_max_len = $db_big_31bit");
  my $prefixq=$prefix;
  $prefixq=~s@([%_\\])@\\$1@g; # Imp: likeq() Dat: MySQL-specific quoting for LIKE # Imp: more metachars?
  my $sth=db_query("SELECT principal, descr,
    GROUP_CONCAT(tag ORDER BY tag SEPARATOR ' ')
    FROM files LEFT OUTER JOIN tags ON
         files.ino=tags.ino AND files.fs=tags.fs
    WHERE principal LIKE ?
    GROUP BY files.ino, files.fs", $prefixq.'%');
  # ^^^ Dat: MySQL is smart enough to optimize away `x LIKE '%''
  my($principal,$descr,$tags);
  my $C=0; my $nbytes=0;
  while (($principal,$descr,$tags)=$sth->fetchrow_array()) {
    $tags="" if !defined $tags; # Dat: no tags
    print STDERR "warning: removed newline from file name\n" if
      $principal=~s@\n+@@g;
    my $E="# file: $principal\nuser.mmfs.description".
      getfattr_eqvalq($descr)."\nuser.mmfs.tags".getfattr_eqvalq($tags)."\n\n";
    if (!print($F $E)) {
      print STDERR "warning: write error: $!\n";
      last
    }
    $C++; $nbytes+=length($E);
  }
  $sth->finish();
  print STDERR "DB_ATTR_DUMP prefix=($prefix) nfiles=$C nbytes=$nbytes\n" if $config{'verbose.level'};
}

#** @param $F IO-handle to be read
sub mydb_add_tags_from_io($$) {
  my($real,$F)=@_;
  print STDERR "DB_ADD_TAGS_FROM_IO\n" if $config{'verbose.level'};
  my $line;
  my $ntags=0;
  my %added_tags; # Imp: empty it when reaches 10000 etc. (ruins $ntags)
  db_transaction(sub {
    while (defined($line=<$F>)) {
      next if $line!~m@\S@ or $line=~m@\A\s*#@;
      my @newtags;
      if ($line=~s@\A\Quser.mmfs.tags="@@) {
        chomp($line); pos($line)=0;
        while ($line=~m@\\.|(")@sg) {
          if (defined $1) { substr($line,pos($line)-length($1))=""; last }
        }
        # ^^^ Imp: syntax error when no trailing quote
        $line=decode_cq($line);
      } elsif ($line=~m@\A[^="]+="@ or $line=~m@\A\Quser.@) {
        next
      }
      for my $tag (split' ',$line) {
        verify_tag($tag);
        if ($@) {
          print STDERR "warning: syntax error in tags file $real, line $.; line ignored\n";
          @newtags=(); last
        }
        push @newtags, $tag;
      }
      for my $tag (@newtags) { next if exists $added_tags{$tag};
        # vvv Dat: similar to mydb_insert_tag()
        # vvv Imp: is `INSERT IGNORE' much faster?
        my $rv=db_do("INSERT INTO tags (tag,ino,fs) VALUES (?,0,'') ON DUPLICATE KEY UPDATE tag=VALUES(tag)", $tag);
        print STDERR "DB_ADD_TAGS_FROM_IO new tag=($tag) rv=$rv\n" if $config{'verbose.level'};
        $ntags++; $added_tags{$tag}=1;
      }
    }
  });
  print STDERR "DB_ADD_TAGS_FROM_IO ntags=($ntags)\n" if $config{'verbose.level'};
}

#** Dat: this is dangerous
sub mydb_purgeallmeta() {
  # !! test with long and lot of tags
  # vvv Dat: no serious need of transaction on `taggings')
  print STDERR "DB_PURGEALLMETA\n" if $config{'verbose.level'};
  db_transaction(sub {
    # vvv Imp: transactions
    db_do("TRUNCATE TABLE taggings");
    db_do("TRUNCATE TABLE files");
    db_do("TRUNCATE TABLE tags");
  });
  print STDERR "DB_PURGEALLMETA finished.\n" if $config{'verbose.level'};
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
  print STDERR "info: diemsg: $msg\n" if $config{'verbose.level'};
  $msg=~s@(?::\s|\n).*@@s;
  ($dienerrnos{$msg} or -1*Errno::EPERM)
}


# --- FUSE-relanted functions, starting with my_*()

# vvv Dat: SUXX: cannot kill processes using the mount point
#     Dat: cannot reconnect
#my @do_umount;
sub cleanup_umount() {
  if (defined $config{'mount.point'}) {
    system('fusermount -u -- '.fnq($config{'mount.point'}).' 2>/dev/null'); # Imp: hide only not-mounted errors, look at /proc/mounts
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

#** Removes /root/, prepends $config{'root.prefix'}.
#** @return undef if not starting with root (or if result would start with
#**   $config{'mount.point'}); filename otherwise
sub sub_to_real($) {
  my $fn=$_[0];
  return undef if $fn!~s@\A/root(?=/|\Z(?!\n))@@;
  ## Dat: now substr($fn,0,1) eq '/', so an empty root_prefix would yield /
  substr($fn,0,0)=(0==length($config{'root.prefix'})) ? '.' : $config{'root.prefix'};
  $fn="/" if 0==length($fn);
  #print STDERR "SUB_TO_REAL() real=$fn\n";
  my $mpoint=$config{'mount.point'};
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
  print STDERR "GETATTR($fn)\n" if $config{'verbose.level'};
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
  } elsif ($fn eq '/tag' or $fn eq '/untag' or $fn eq '/tagged' or
    $fn eq '/search' or $fn eq '/adm' or $fn eq '/adm/fixprincipal' or
    $fn eq '/adm/fixunlink',
    #or $fn eq '/adm/dumpattr'
    ) {
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
    # Imp: Errno::EACCES for $config{'mount.point'}/$config{'mount.point'}
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
  print STDERR "GETDIR($dir)\n" if $config{'verbose.level'};
  if ($dir eq '/') {
    # Dat: we need '.' and '..' for both / and others
    return ('.','..','root','search','tag','untag','tagged','adm', 0); # $errno
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
  } elsif ($dir eq '/adm') {
    return ('.','..','fixprincipal','fixunlink',0);
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
  print STDERR "OPEN($fn,$flags)\n" if $config{'verbose.level'};
  return -1*Errno::EROFS if $config{'read.only.p'} and ($flags&O_ACCMODE)!=O_RDONLY;
  #print "OPEN_OK\n";
  return 0
}

sub my_read($$$) {
  my($fn,$size,$offset)=@_;
  my $real;
  my $F;
  #$offset=0 if !defined $offset;
  print STDERR "READ($fn,$size,$offset)\n" if $config{'verbose.level'};
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
  print STDERR "MKNOD($fn,$mode,$rdev)\n" if $config{'verbose.level'};
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
  print STDERR "WRITE($fn,".length($S).",$offset)\n" if $config{'verbose.level'};
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
  print STDERR "UNLINK($fn)\n" if $config{'verbose.level'};
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
      my $may_p=eval { mydb_may_unlink_multi($fn) };
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
      print STDERR "info: unlink error: $@" if $@;
    }
  }
  return 0
}

sub my_rmdir($) {
  my($fn)=@_;
  my $real;
  print STDERR "RMDIR($fn)\n" if $config{'verbose.level'};
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
      print STDERR "info: rmdir error: $@" if $@;
    }
    return 0
  }
}

sub my_mkdir($$) {
  my($fn,$mode)=@_;
  my $real;
  # Dat: FUSE calls: GETATTR(), MKDIR(), GETATTR()
  print STDERR "MKDIR($fn,$mode)\n" if $config{'verbose.level'};
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/(?:tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
      my $tag=$1;
      eval { mydb_insert_tag($tag); };
      return diemsg_to_nerrno();
    } elsif ($fn eq '/adm/repair_taggings') {
      eval { mydb_repair_taggings(); };
      return diemsg_to_nerrno();
      # ^^^ Dat: although we return 0 here, FUSE will GETATTR() after MKDIR(),
      #          and return Errno::ENOENT to the application.
    } elsif ($fn eq '/adm/reload_fss') {
      eval { mydb_fill_dev_to_fs; };
      return diemsg_to_nerrno();
      # ^^^ Dat: although we return 0 here, FUSE will GETATTR() after MKDIR(),
      #          and return Errno::ENOENT to the application.
    } elsif ($fn eq '/adm/purgeallmeta') {
      return -1*Errno::EOPNOTSUPP if !$config{'enable.purgeallmeta.p'};
      eval { mydb_purgeallmeta(); };
      return diemsg_to_nerrno();
      # ^^^ Dat: although we return 0 here, FUSE will GETATTR() after MKDIR(),
      #          and return Errno::ENOENT to the application.
    } elsif ($fn=~m@/adm/fixunlinkino:([0-9a-fA-F]+),([0-9a-fA-F]+),([0-9a-fA-F]+)\Z(?!\n)@) {
      return myhelper_fixunlinkino($1,$2,$3);
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
  print STDERR "CHMOD($fn,$mode)\n" if $config{'verbose.level'};
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
  print STDERR "CHOWN($fn,$uid,$gid)\n" if $config{'verbose.level'};
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
  print STDERR "UTIME($fn,$atime,$mtime)\n" if $config{'verbose.level'};
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
  print STDERR "SYMLINK($target,$fn)\n" if $config{'verbose.level'};
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
  print STDERR "LINK($oldfn,$fn)\n" if $config{'verbose.level'};
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

sub myhelper_fixunlinkino($$$) { # !!
  my($st_dev_hex,$st_ino_hex,$st_nlink_hex)=@_;
  my $st_dev=hex($st_dev_hex); my $st_ino=hex($st_ino_hex);
  my $st_nlink=hex($st_nlink_hex);
  if ($st_nlink==1) { # Dat: this is to force the caller think to $st_nlink
    # Dat: we ignore the target name inside /adm/fixprincipal
    eval { mydb_unlink_last(sprintf("inode/%X,%X",$st_dev,$st_ino),
      $st_dev, $st_ino) };
  }
  return diemsg_to_nerrno()
}

#** Dat: FUSE doesn't call us when $oldfn eq $fn.
sub my_rename($$) {
  my($oldfn,$fn)=@_;
  my($oldreal,$real);
  print STDERR "RENAME($oldfn,$fn)\n" if $config{'verbose.level'};
  if (!defined($real=sub_to_real($fn))) {
    if ($fn=~m@/(tag|untag|tagged)/([^/]+)/[^/]+\Z(?!\n)@) {
      # Dat: mydb_op_tag() and mydb_op_untag() verify if $oldfn is a mirrored filename,
      #      no need to check defined(sub_to_real($oldfn))
      my $op=$1; my $tag=$2;
      return -1*Errno::EPERM if $tag eq ':all' and $op ne 'untag';
      eval { $op eq 'tag' ? mydb_op_tag($oldfn,$tag) : mydb_op_untag($oldfn,$tag) };
      return diemsg_to_nerrno()
    } elsif ($fn=~m@/adm/fixprincipal/[^/]+\Z(?!\n)@ &&
             defined($oldreal=sub_to_real($oldfn))) {
      # Dat: we ignore the target name inside /adm/fixprincipal
      eval { mydb_rename_fn_to($oldfn) };
      return diemsg_to_nerrno()
    } elsif ($fn=~m@/adm/fixunlink/[^/]+\Z(?!\n)@ &&
             defined($oldreal=sub_to_real($oldfn))) {
      # Dat: this is can be a little dangerous (forgets all metainformation)
      eval { mydb_unlink_last($oldfn,undef,undef,1) }; # Dat: unlink by_principal
      return diemsg_to_nerrno() if $@;
      eval { mydb_unlink_last($oldfn) };
      return diemsg_to_nerrno()
    } elsif ($fn eq '/adm/dumpattr' and
             defined($oldreal=sub_to_real($oldfn))) {
      my($F);
      return -1*$! if !open($F, '>', $oldreal);
      # vvv imp: dump only parts...
      eval { mydb_attr_dump('', $F) };
      return -1*$! if !close($F);
      return diemsg_to_nerrno()
    } elsif ($fn eq '/adm/addtags' and
             defined($oldreal=sub_to_real($oldfn))) {
      my($F);
      return -1*$! if !open($F, '<', $oldreal);
      # vvv imp: dump only parts...
      eval { mydb_add_tags_from_io($oldreal,$F) };
      return -1*$! if !close($F);
      return diemsg_to_nerrno()
    } elsif ($fn=~m@/(tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
      my $op=$1; my $tag=$2;
      if ($oldfn=~m@/(tag|untag|tagged)/([^/]+)\Z(?!\n)@) {
        my $oldop=$1; my $oldtag=$2;
        eval { mydb_rename_tag($oldtag,$tag) };
        return diemsg_to_nerrno()
      }
    }
  } elsif (!defined($oldreal=sub_to_real($oldfn))) {
    # Dat: although mv(1) can get EXDEV here, we don't want it to, because
    #      then it tries to copy recursively. So we return EPERM.
    #return -1*Errno::EPERM
  } elsif (!rename($oldreal,$real)) {
    return -1*$!
  } else {
    eval { mydb_rename_fn_to($fn) };
    return diemsg_to_nerrno()
  }
  return -1*Errno::EPERM
}

sub my_readlink($) {
  my($fn)=@_;
  my $real;
  my $ret;
  print STDERR "READLINK($fn)\n" if $config{'verbose.level'};
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
  print STDERR "TRUNCATE($fn,$tosize)\n" if $config{'verbose.level'};
  if (!defined($real=sub_to_real($fn))) {
    return -1*Errno::EPERM
  } elsif (!truncate($real,$tosize)) {
    return -1*$!
  } else {
    return 0
  }
}

sub my_statfs() {
  print STDERR "STATFS()\n" if $config{'verbose.level'};
  return -1*Errno::ENOANO;
}

sub my_flush($) {
  my($fn)=$_[0];
  print STDERR "FLUSH($fn)\n" if $config{'verbose.level'};
  return 0;
}

sub my_fsync($) {
  my($fn)=$_[0];
  print STDERR "FSYNC($fn)\n" if $config{'verbose.level'};
  return 0;
}

sub my_release($$) {
  my($fn,$flags)=@_;
  print STDERR "RELEASE($fn)\n" if $config{'verbose.level'};
  return 0;
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
sub my_listxattr($) {
  my($fn)=@_;
  my $real;
  my @attrs;
  print STDERR "LISTXATTR($fn)\n" if $config{'verbose.level'};
  # Dat: getfattr(1) `getfattr -d' needs the "user.mmfs." prefix
  if ($fn eq '/root' or !defined($real=sub_to_real($fn))) {
    # Dat: `meta/root' is also a fakenode, since it doesn't have a valid
    #      $localname
    push @attrs, 'user.mmfs.fakenode';
  } else {
    push @attrs, 'user.mmfs.realnode';
    push @attrs, 'user.mmfs.tags'; # Dat: lazy here, even for files with no tags
    push @attrs, 'user.mmfs.description'; # Dat: lazy here, even for files with an empty description
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
  if ($attrname eq 'user.mmfs.fakenode') {
    return defined($real) ? 0 : "1"
  } elsif ($attrname eq 'user.mmfs.realnode') {
    return defined($real) ? "1" : 0
  } elsif ($attrname eq 'user.mmfs.tags') {
    return 0 if !defined $real;
    my @tags=eval { mydb_file_get_tags($fn) };
    return '' if $@ eq "localname not a file\n"; # Imp: test after preprocessing
    return diemsg_to_nerrno() if $@;
    join(' ',@tags)
  } elsif ($attrname eq 'user.mmfs.description') {
    return 0 if !defined $real;
    my $descr=eval { mydb_file_get_descr($fn) };
    return '' if $@ eq "localname not a file\n"; # Imp: test after preprocessing
    return diemsg_to_nerrno() if $@;
    defined$descr ? $descr : ''
  }
}

sub my_getxattr($$) {
  my($fn,$attrname)=@_;
  print STDERR "GETXATTR($fn,$attrname)\n" if $config{'verbose.level'};
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
  if ($attrname eq 'user.mmfs.tags') {
    eval { mydb_file_set_tagtxt($fn,$attrval,'set') };
    return diemsg_to_nerrno();
  } elsif ($attrname=~m@\A\Quser.mmfs.tags.\E(tag|untag|modify)\Z(?!\n)@) {
    eval { mydb_file_set_tagtxt($fn,$attrval,$1) };
    return diemsg_to_nerrno();
  } elsif ($attrname eq 'user.mmfs.description') {
    eval { mydb_file_set_descr($fn,$attrval) };
    return diemsg_to_nerrno();
  } elsif (my_getxattr_low($fn,$attrname) eq $attrval) {
    # ^^^ Imp: `eq' on error messages
    # Dat: this is so `setxattr --restore' runs cleanly on `user.mmfs.realnode'
    return 0
  }
  return -1*Errno::EPERM
}

sub my_setxattr($$$$) {
  my($fn,$attrname,$attrval,$flags)=@_;
  print STDERR "SETXATTR($fn,$attrname,$attrval,$flags)\n" if $config{'verbose.level'};
  my_setxattr_low($fn,$attrname,$attrval,$flags)
}

#** Dat: this is fake, see `man 5 attr' and `man 2 lgetxattr' for more
#** Dat: `setfattr -x attrname filename'
sub my_removexattr($$) {
  my($fn,$attrname)=@_;
  print STDERR "REMOVEXATTR($fn,$attrname)\n" if $config{'verbose.level'};
  my_setxattr_low($fn,$attrname,"",0); # Imp: smarter
  # vvv Imp: disinguish "0" and 0 (with Scalar::Util?)
  #if (my_getxattr_low($fn,$attrname)eq"0") { # Dat: no such attribute
  #  return -1*Errno::ENOATTR
  #} else {
  #  return -1*Errno::EPERM
  #}
}

# --- main()

die "config already read\n" if @config_argv;
config_reread();

die "$0: extra args: @ARGV\n" if "@ARGV" ne "--";
die "$0: empty config key mount.point, see README.txt\n" if 0==length($config{'mount.point'});
die "$0: cannot find mount.point\n" if !defined($config{'mount.point'}=Cwd::abs_path($config{'mount.point'})) or
  substr($config{'mount.point'},0,1)ne"/" or length($config{'mount.point'})<2 or $config{'mount.point'}=~m@//@;
#print STDERR "D".(-d $config{'mount.point'});
# vvv SUXX: it works only every 2nd time because of fusermount stale etc.
my @L=lstat($config{'mount.point'});
#print STDERR "$!..\n" if !@L;
if ((@L or $! !=Errno::ENOTCONN) and !(-d _)) {
  die "$0: cannot create mount.point $config{'mount.point'}: $!\n" if !mkdir($config{'mount.point'});
}

$config{'root.prefix'}=~s@//+@/@g;
$config{'root.prefix'}=~s@/*\Z(?!\n)@/@;
$config{'root.prefix'}=~s@\A/+@/@;
#$all_fs=config_get('default.fs','F');
#{ my @st=lstat("$config{'root.prefix'}/.");
#  die "$0: cannot stat --root-prefix=: $config{'root.prefix'}\n" if !@st;
#  $all_dev=$st[0];
#  #die "all_dev=$all_dev\n";
#}
db_connect();
mydb_fill_dev_to_fs();

system('fusermount -u -- '.fnq($config{'mount.point'}).' 2>/dev/null'); # Imp: hide only not-mounted errors, look at /proc/mounts
print STDERR "movemetafs v$VERSION server, starting Fuse::main on mount.point=$config{'mount.point'}\n" if $config{'verbose.level'};
print STDERR "Press Ctrl-<C> to exit (and then umount manually).\n" if $config{'verbose.level'};
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

Fuse::main(mountpoint=>$config{'mount.point'},
  #mountopts=>'allow_other', # etc., echo user_allow_other >>/etc/fuse.conf
  #mountopts=>'user_xattr', # Dat: not possible to pass user_xattr here...
  #treaded=>0, # Dat: threaded=>1 needs ithreads and precautions
  @ro_ops,
  ($config{'read.only.p'} ? () : @write_ops),
);
# ^^^ Dat: might die with:
#     fusermount: fuse device not found, try 'modprobe fuse' first
#     could not mount fuse filesystem!

__END__
