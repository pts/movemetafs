#! /bin/bash --
# by pts@fazekas.hu at Thu Jan 11 23:45:43 CET 2007
set -ex
/sbin/modprobe rfsdelta
#** @example OLDDEV="252, 0"
OLDDEV="`ls -l /dev/rfsdelta-event | perl -ne 'my @L=split(/\s+/,$_); print "$L[4] $L[5]\n"'`"
set x `</proc/rfsdelta perl -ne 'print if s@^\0*devnumbers: c (\d+) (\d+)$@$1 $2@'`
test "$2" # "253"
test "$3" # "0"
if test "$OLDDEV" = "$2, $3"; then
  :
else
  rm -f /dev/rfsdelta-event
  mknod /dev/rfsdelta-event c "$2" "$3"
fi

chmod 400  /dev/rfsdelta-event
chown pts: /dev/rfsdelta-event
