#
# example movemetafs.conf (configuration file for movemetafs)
# by pts@fazekas.hu at Thu Jan  4 18:51:18 CET 2007
#
# Keep this file confidential, because it contains a database connection
# password.
#
db.dsn: dbi:mysql:database=movemetafs:mysql_socket=/var/run/mysql.sock
db.username: movemetafs_rw
db.auth: put_password_here
# ^^^ Dat: make sure that password matches the one in recreate.sql
#db.onconnect.1: SET NAMES 'utf8' COLLATE 'utf8_general_ci'
#default.fs: "G"
