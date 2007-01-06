#
# example movemetafs.conf
# by pts@fazekas.hu at Thu Jan  4 18:51:18 CET 2007
#
db.dsn: dbi:mysql:database=movemetafs:mysql_socket=/var/run/mysql.sock
db.username: movemetafs_rw
db.auth: put_password_here
# ^^^ Dat: make sure that password matches the one in recreate.sql
#db.onconnect.1: SET NAMES 'utf8' COLLATE 'utf8_general_ci'
#all.fs: "G"
