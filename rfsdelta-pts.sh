#! /bin/bash --
# by pts@fazekas.hu at Thu Jan 11 23:45:43 CET 2007
set -ex
/sbin/modprobe rfsdelta
chmod 400  /dev/rfsdelta-event
chown pts: /dev/rfsdelta-event
