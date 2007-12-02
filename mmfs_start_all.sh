#! /bin/bash --
#
# mmfs_start_all.sh -- start all movemetafs services
# by pts@fazekas.hu at Fri Jan 19 23:25:51 CET 2007
#

MYDIR="${0%/*}"; test "$MYDIR" = "$0" && MYDIR=.
set -ex
cd "$MYDIR"

test -w .
test -w mysqldbdir
type -p fusermount
test -x "`type -p fusermount`"
perl -MFuse -MDBD::mysql -e0
# vvv Dat: Transport endpoint not connected for `test -d'
#test -d "$HOME/mmfs" ||
mkdir -p "$HOME/mmfs" || true
#test -d "$HOME/mmfs"

if perl -mIO::Socket::UNIX -e 'die $! if !IO::Socket::UNIX->new("mysqldbdir/our.sock")'; then
  :
else
  # vvv Imp: check for already running etc
  screen -S mmfs_mysqld -d -m mysqldbdir/mysqld_run.sh
  LEFT=10
  # vvv Dat: give mysqld time to come up
  until perl -mIO::Socket::UNIX -e 'die $! if !IO::Socket::UNIX->new("mysqldbdir/our.sock")'; do
    test "$LEFT" = 0 && exit 11
    sleep 1
    let LEFT=LEFT-1
  done
fi

if test -d "${HOME}/mmfs/tag"; then
  :
else
  ./mmfs_fuse.pl --test-db
  screen -S mmfs_fuse -d -m ./mmfs_fuse.pl
  LEFT=5
  until test -d "${HOME}/mmfs/tag"; do
    test "$LEFT" = 0 && exit 12
    sleep 1
    let LEFT=LEFT-1
  done
fi

if test -e /proc/rfsdelta-event && test -r /dev/rfsdelta-event; then
  :
else
  # Dat: to /etc/sudoers:
  #      pts ALL = NOPASSWD: /usr/local/sbin/rfsdelta-pts.sh
  sudo /usr/local/sbin/rfsdelta-pts.sh
  test -e /proc/rfsdelta-event || exit 15
  test -c /dev/rfsdelta-event || exit 13
fi
test -r /dev/rfsdelta-event || exit 14 # Imp: euid

if GOT="`2>&1 true </dev/rfsdelta-event`"; then
  # Dat: nobody is reading it, no `Device 
  screen -S mmfs_rfsdelta -d -m ./mmfs_rfsdelta_watcher.pl
  # vvv Imp: try to open after 3 seconds, avoid deadlock
  #while GOT="`2>&1 true </dev/rfsdelta-event`"
elif test "$GOT" = "${GOT#*evice or resource busy*}"; then
  # Dat: other error
  exit 15
elif test "$GOT" = "${GOT#*ermission denied*}"; then
  # Dat: not chmodded properly
  exit 16
else
  # Dat: other error
  exit 17
fi

: All services started OK
