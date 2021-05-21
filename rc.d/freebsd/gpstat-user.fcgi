#!/bin/sh
#
# $FreeBSD: user (gpstat), v1.5 2007/09/30 23:10:55 flood Exp 
#
# PROVIDE: gpstat
# REQUIRE: NETWORKING
#
# Add the following line to /etc/rc.conf to enable gpstat_user:
#
# gpstat_user_enable="YES"
#

gpstat_user_enable="${gpstat_user_enable-NO}"
. /etc/rc.subr


name=gpstat_user
rcvar=`set_rcvar`

prefix=/home/gpstat
procname=fcgi-gpstat-user
pidfile=/var/run/gpstat/user.fcgi.pid
required_files="${prefix}/redefine.conf"
command="${prefix}/fcgi/user"

load_rc_config ${name}

run_rc_command "$1"
