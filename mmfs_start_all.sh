#! /bin/bash --
#
# mmfs_start_all.sh -- start all movemetafs services
# by pts@fazekas.hu at Fri Jan 19 23:25:51 CET 2007
#

MYDIR="${0%/*}"; test "$MYDIR" = "$0" && MYDIR=.
set -ex
cd "$MYDIR"
if perl -mIO::Socket::UNIX -e 'die $! if !IO::Socket::UNIX->new("mysqldbdir/our.sock")'; then
  :
else
  # vvv Imp: check for already running etc
  screen -d -m mysqldbdir/mysqld_run.sh
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
  screen -d -m ./mmfs_fuse.pl
  LEFT=5
  until test -d "${HOME}/mmfs/tag"; do
    test "$LEFT" = 0 && exit 12
    sleep 1
    let LEFT=LEFT-1
  done
fi

if test -e /proc/rfsdelta-event; then
  :
else
  sudo /usr/local/sbin/rfsdelta-pts.sh
  test -e /proc/rfsdelta-event || exit 15
  test -c /dev/rfsdelta-event || exit 13
fi
test -r /dev/rfsdelta-event || exit 14 # Imp: euid

if GOT="`2>&1 true </dev/rfsdelta-event`"; then
  # Dat: nobody is reading it, no `Device 
  screen -d -m ./mmfs_rfsdelta_watcher.pl
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
