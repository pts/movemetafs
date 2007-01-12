#! /bin/sh
eval '(exit $?0)' && eval 'PERL_BADLANG=x;PATH="$PATH:.";export PERL_BADLANG\
 PATH;exec perl -x -S -- "$0" ${1+"$@"};#'if 0;eval 'setenv PERL_BADLANG x\
;setenv PATH "$PATH":.;exec perl -x -S -- "$0" $argv:q;#'.q
#!perl -w
+push@INC,'.';$0=~/(.*)/s;do(index($1,"/")<0?"./$1":$1);die$@if$@__END__+if 0
;#Don't touch/remove lines 1--7: http://www.inf.bme.hu/~pts/Magic.Perl.Header
#
# mmfs_rfsdelta_watcher.pl -- watch for filesystem changes
# by pts@fazekas.hu at Thu Jan 11 23:49:26 CET 2007
#
# Dat: see the README of rfsdelta
#      (in http://www.inf.bme.hu/~pts/rfsdelta-latest.tar.gz)
# Imp: less verbose, ignore `info:'
#
use integer;
use strict;

select(STDERR); $|=1;
select(STDOUT); $|=1;

# vvv Dat: for "$!"
$ENV{LANGUAGE}=$ENV{LC_MESSAGES}='C';

my $rfsdelta_event="/dev/rfsdelta-event";
my $mmfs_mount_point="$ENV{HOME}/mmfs";
#** Must be absolute or empty, never endig with `/'
my $mmfs_root_prefix='';

# vvv Dat: sanity check for live $mmfs_mount_point
# vvv Dat: usually `Transport endpoint is not connected' for stale FUSE mounts
# vvv Dat: usually `Permission denied' (?) for different user
my($mmfs_dev,$mmfs_root_ino);
die "error: mount.point $mmfs_mount_point: $!\n" unless
  ($mmfs_dev,$mmfs_root_ino)=lstat($mmfs_mount_point);

my %dev_to_mprefix;
#** Fills %dev_to_mprefix
sub rescan_mounts() {
  die if !open(my($F), '<', '/proc/mounts');
  %dev_to_mprefix=();
  my $line;
  my $root_found_p=0;
  local $/="\n";
  while (defined($line=<$F>)) {
    if ($line=~m@\A(/[^ ]*) ([^ ]+) @) {
      # Dat: $1 might be "/dev/root", but we don't care
      my $mpoint=$2;
      my($dev,$ino_dummy)=lstat($mpoint);
      if (defined $dev) {
        #$dev=($dev&0xff)|(($dev>>8)<<20); # Dat: Linux-specific and Perl-specific 0xFD06 -> 0xFD00006
        $mpoint=~s@/+\Z(?!\n)@@; # Dat: from `/' to `'
        $dev_to_mprefix{$dev}=$mpoint;
        print STDERR "info add dev=0x".sprintf("%X",$dev)." mprefix=($mpoint)\n";
        $root_found_p=1 if $mpoint eq '';
      }
    }
  }
  close($F);
  # vvv Imp: how can we reach `no mpoints'
  die "error: no mpoints found in /proc/mounts\n" if !%dev_to_mprefix;
  die "error: dir / not found in /proc/mounts\n" if !$root_found_p;
  undef
}

rescan_mounts();

# vvv Dat: sanity check for $mmfs_mount_point
{ die if !open(my($F), '<', '/proc/mounts');
  my $searchprefix="/dev/fuse $mmfs_mount_point fuse ";
  my $line;
  my $found_p=0;
  while (defined($line=<$F>)) {
    if (substr($line,0,length($searchprefix)) eq $searchprefix) {
      $found_p=1; last
    }
  }
  close($F);
  die "error: mount.point $mmfs_mount_point not FUSE\n" if !$found_p;
}

sub do_unlink_last($$$) {
  my($dev,$ino,$fn)=@_;
  my $mprefix;
  # !! disable unlink of principal if $nlink>1 (cannot do it from here)
  if (!defined($mprefix=$dev_to_mprefix{$dev})) {
    print STDERR "warning: unknown dev: $dev\n";
    return
  }
  #my $mfn=$mprefix.$fn;
  #if (substr($mfn,0,length($mmfs_root_prefix)) ne $mmfs_root_prefix) {
  #  print STDERR "info: outside root prefix, ignoring\n";
  #  return
  #}
  #die(sprintf("$mmfs_mount_point/adm/fixprincipalino:%X,%X:%s",
  #  $dev, $ino, $mfn));
  # vvv Imp: possibly go by $ino (with symlink()?)
  # vvv Dat: we go this way since unlink(2) might already have succeeded
  my $fu=sprintf("%s/adm/fixunlinkino:%X,%X,1",
    $mmfs_mount_point, $dev, $ino);
  print STDERR "info: issuing mkdir ($fu)\n";
  print STDERR "warning: mkdir failed: $!\n" if mkdir($fu) or
    "$!" ne "No such file or directory"; # Dat: ENOENT
}

# vvv Imp: sudo modprobe etc.
die "error: open rfsdelta-event $rfsdelta_event: $!\n"
  if !open STDIN, '<', $rfsdelta_event;
$/="\0";
print STDERR "info: waiting for rfsdelta events... (Press Ctrl-<C> to abort.)\n";
while (<STDIN>) {
  s@\0@@;
  if (m@\A[1-3]\Z(?!\n)@) {
    print STDERR "info: (u)mount event: $_\n";
    rescan_mounts();
    next
  }
  if (!m@\A([a-zA-Z])([0-9A-F]+),@) {
    print STDERR "warning: syntax error #1, ignoring event: $_\n"; next
  }
  my($type,$dev)=($1,hex($2));
  $dev=($dev&0xff)|(($dev>>20)<<8); # Dat: Linux-specific and Perl-specific 0xFD06 <- 0xFD00006
  if ($dev==$mmfs_dev) {
    print STDERR "info: ignoring event on mmfs dev: $_\n"; next
  }
  my($ino,$mode,$nlink,$rdev,$devname,$mprefix);
  my $fn=$_;
  if ($fn=~s@\A[a-zA-Z][^,]+,([0-9A-F]+),([0-9A-F]+),([0-9A-F]+),([0-9A-F]+):([^:/]+):(?=/)@@) {
    ($ino,$mode,$nlink,$rdev,$devname)=(hex($1),hex($2),hex($3),hex($4),$5);
  } elsif ($fn=~s@\A[^,]+,[?]:([^:/]+):(?=/)@@) {
    ($devname)=($1);
  } else {
    print STDERR "warning: syntax error #2, ignoring event: $_\n"; next
  }
  if ($type eq 'a' and defined $ino) {
    # !! track cross-device renames
    print STDERR "info: got move-target event: $_\n";
    if (!defined($mprefix=$dev_to_mprefix{$dev})) {
      print STDERR "warning: unknown dev: $dev\n";
      next
    }
    my $mfn=$mprefix.$fn;
    if (substr($mfn,0,length($mmfs_root_prefix)) ne $mmfs_root_prefix) {
      print STDERR "info: outside root prefix, ignoring\n";
      next
    }
    #die(sprintf("$mmfs_mount_point/adm/fixprincipalino:%X,%X:%s",
    #  $dev, $ino, $mfn));
    # vvv Imp: possibly go by $ino (with symlink()?)
    my $from="$mmfs_mount_point/root".substr($mfn,length($mmfs_root_prefix));
    my $to="$mmfs_mount_point/adm/fixprincipal/:any";
    # Dat: this works for folder renames
    print STDERR "info: issuing rename ($from) -> ($to)\n";
    print STDERR "warning: rename failed: $!\n" if !rename($from,$to);
  } elsif ($type eq 'u' and defined $ino and $nlink==1) {
    print STDERR "info: got unlink-last event: $_\n";
    do_unlink_last($dev,$ino,$fn);
  } elsif ($type eq 'R' and defined $ino) {
    print STDERR "info: got rmdir event: $_\n";
    do_unlink_last($dev,$ino,$fn);
  } else {  
    print STDERR "info: got boring event: $_\n";
  }
}
