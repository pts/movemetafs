#! /bin/sh
eval '(exit $?0)' && eval 'PERL_BADLANG=x;PATH="$PATH:.";export PERL_BADLANG\
 PATH;exec perl -x -S -- "$0" ${1+"$@"};#'if 0;eval 'setenv PERL_BADLANG x\
;setenv PATH "$PATH":.;exec perl -x -S -- "$0" $argv:q;#'.q
#!perl -w
+push@INC,'.';$0=~/(.*)/s;do(index($1,"/")<0?"./$1":$1);die$@if$@__END__+if 0
;#Don't touch/remove lines 1--7: http://www.inf.bme.hu/~pts/Magic.Perl.Header
# by pts@fazekas.hu at Thu Jan 11 23:49:26 CET 2007
#
my $

# vvv Imp: sudo modprobe etc.
die unless open STDIN, '<', "/dev/rfsdelta";
$/="\0";
while (<STDIN>) {
  s@\0@@d;
  if (m@\A