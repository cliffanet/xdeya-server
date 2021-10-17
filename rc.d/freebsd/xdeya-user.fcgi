#!/bin/sh
#
# $FreeBSD: user (xdeya), v1.5 2007/09/30 23:10:55 flood Exp 
#
# PROVIDE: xdeya
# REQUIRE: NETWORKING
#
# Add the following line to /etc/rc.conf to enable xdeya_user:
#
# xdeya_user_enable="YES"
#

xdeya_user_enable="${xdeya_user_enable-NO}"
. /etc/rc.subr


name=xdeya_user
rcvar=`set_rcvar`

prefix=/home/xdeya-server
procname=fcgi-xdeya-user
pidfile=/var/run/xdeya/user.fcgi.pid
required_files="${prefix}/redefine.conf"
command="${prefix}/fcgi/user"

load_rc_config ${name}

run_rc_command "$1"
