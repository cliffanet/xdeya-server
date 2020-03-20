package CUser::Auth;

use Clib::strict8;

use Clib::DB::MySQL 'DB';
use Clib::Web::Controller;

use Encode;
use Digest::MD5 qw(md5_hex);

my $accf = 'accterm';

sub _root :
        AllowNoAuth
        Title('Авторизация')
        ReturnBlank
{
    my @p = ();
    my $p = wparam();
    
    # ссылка для редиректа
    my ($disp, @disp) = ();
    if (my $path = $p->raw('ar')) {
        debug('auth-form redirect path: %s', $path);
        ($disp, @disp) = webctrl_search($path);
    }
    elsif (my $href = WebUser::redirect_referer()) {
        debug('auth-form redirect referer: %s', $href);
        ($disp, @disp) = WebUser::disp_search($href);
    }
    if ($disp) {
        my $ar = WebUser::pref_short($disp->{path}, @disp);
        if ($ar && ($ar ne 'auth')) {
            $ar = '/' . $ar;
            push @p, ar => $ar;
            debug('auth-form redirect to: %s', $ar);
        }
    }
    
    return 'auth_form', @p;
}

sub passenc {
    my $pass = shift;
    defined($pass) || return;
    return '' if $pass eq '';
    
    if (utf8::is_utf8($pass)) {
        $pass = encode_utf8($pass);
    }
    
    my $code = 'hd4ff38fv';
    
    return 'md51:'.md5_hex($pass, $code);
}

sub login :
        AllowNoAuth
        Title('Авторизация (выполнение)')
        ReturnOperation
{
    my $p = wparam();
    my $login    = $p->str('l');
    my $password = $p->raw('p');
    $password = '' if !defined($password);
    my $authredir = $p->raw('ar');
    
    my @err = ();
    
    if ($authredir) {
        push @err, ar => $authredir;
    }
    
    # Проверка логина
    if ($login eq '') {
        logauth("AUTH: Empty login");
        return err => c(state => loginerr => 'empty'), @err;
    }
    
    # Хорошо бы передавать логин через msg, чтобы в случае редиректа он уже был автоматически введён,
    # однако, если будет ошибка авторизации (например, при подборе пароля), то каждый раз
    # будет создаваться сессия с сохранённым логином, которая не будет стираться до таймаута,
    # пока не будет открыта страница. При ajax-авторизации такое, например, вообще штатно происходит.
    # Поэтому, чтобы не делать лишних сохранений в БД и вообще лишних действий, сохранять логин не будем
    #push @err, login => $login;
    
    # Проверяем существование аккаунта
    my $user = sqlGet(admin => login => $login);
    
    if (!$user || !$user->{id}) {
        logauth("AUTH: Unknown user: %s", $login);
        return err => c(state => loginerr => 'wrong'), @err;
    }
    
    # Проверяем пароль
    if ($user->{password} eq '') {
        # Пароль пустой - глобальный запрет доступа
        logauth("AUTH: Empty password on user: %s", $login);
        return err => c(state => loginerr => 'wrong'), @err;
    }
    
    if ($user->{password} =~ /^md51\:[0-9a-f]+$/) {
        # Новый md51-формат
        my $pass = CAdmin::Auth::passenc($password);
        if ($user->{password} ne $pass) {
            logauth("AUTH: Failed for user: %s", $login);
            return err => c(state => loginerr => 'wrong'), @err;
        }
    }
    else {
        logauth("AUTH: Unknown password-format for user: %s (%s)", $login, $user->{password});
        return err => c(state => loginerr => 'wrong'), @err;
    }
    
    # Проверка прав доступа
    my $acc = $user->{$accf};
    if ($acc && ($acc eq 'grp')) {
        if (my $gid = $user->{gid}) {
            my $grp = sqlGet(admgrp => $gid);
            $acc = $grp ? $grp->{$accf} : '';
        }
    }
    if (!$acc) {
        logauth("AUTH: Access denied for user: %s", $login);
        return err => c(state => loginerr => 'accdenied'), @err;
    }
    
    logauth("AUTH: Succeful for user: %s (%s)", $login, $user->{login});
    
    # Создаем новую сессию
    my $time = time;
    my %sess = ();
    
    # Определяем таймауты
    my $expire = c(session => 'idle') || 0;
    $sess{expire} = $time + $expire if $expire > 0;
    my $expiremax = c(session => 'max') || 0;
    $sess{expiremax} = $time + $expiremax if $expiremax > 0;
    
    my $sid = session_new(uid => $user->{id})
        || return err => c(state => loginerr => 'sessadd'), @err;
    WebUser::login(user => $user);
    
    # Редирект после авторизации (ссылка должна быть без $href_prefix)
    if ($authredir && ($authredir =~ /^\//)) {
        debug('authredir: %s', $authredir);
        my ($disp, @disp) = webctrl_search($authredir);
        if ($disp) {
            debug('dispatcher for auth redirect found: %s (%s) <- \'%s\'', $disp->{symbol}, $disp->{path}, $authredir);
            $authredir = [$disp->{path}, @disp];
        }
        else {
            logauth('dispatcher for auth redirect not found: %s', $authredir);
        }
    }
    else {
        $authredir = '/';
    }
    
    return ok => c(state => 'loginok'), redirect => $authredir;
}

sub logout :
        Title('Выход из системы')
        ReturnOperation
{
    my %auth = WebUser::auth();
    my $sess = $auth{session}
        || return err => c(state => loginerr => 'nosess');
    
    logauth("AUTH: Logout: %s", ($auth{user}||{})->{login});
    
    WebUser::logout();
    
    return ok => c(state => 'logout'), redirect => 'auth';
}

sub session_new {
    my %p = @_;
    
    my $time = time;
    
    my $skey = int(rand(0xFFFFFFFF));
    my @sess = (
        key     => $skey,
        ip      => $ENV{REMOTE_ADDR} || '',
        create  => Clib::DT::fromtime($time),
        visit   => Clib::DT::fromtime($time),
        @_,
    );
    
    # Пишем в БД
    my $sid = sqlAdd(session => @sess);
    if (!$sid) {
        logauth("AUTH: Can't create session");
        return;
    }
    
    WebUser::login(session => { id => $sid, @sess });
    
    # Всем остальным сессиям говорим "давай-досвидания"
    if (my $uid = $p{uid}) {
        my @sess = sqlSrch(session => uid => $uid, sqlNotEq(id => $sid));
        foreach my $sess (@sess) {
            sqlUpd(session => $sess->{id}, closed => 'other');
        }
    }
    
    # Наконец, всё ок, пишем куки
    Clib::Web::Param::cookieset(sid => $sid, path => '/');
    Clib::Web::Param::cookieset(skey => $skey, path => '/');
    
    return $sid;
}

sub check {
    my %c = WebUser::web_cookie();
    my $ip = $ENV{REMOTE_ADDR};
    
    return
        if !$ip || !$c{sid} || !$c{skey};
    
    my @r = (ip => $ip);
    
    # Ищем и проверяем сессию пользователя
    my ($sess) = sqlSrch(session => id => $c{sid}, key => $c{skey});
    
    if (!$sess) {
        Clib::Web::Param::cookieset(sid => '', path => '/', delete => 1);
        Clib::Web::Param::cookieset(skey => '', path => '/', delete => 1);
        return errno => 'nosess', @r;
    }
    
    push @r, session => $sess;
    
    if (!$sess->{uid}) {
        # Это временная сессия
        return @r;
    }
    
    # Если IP-сессии изменился, сессию принудительно убиваем
    if ($ip ne $sess->{ip}) {
        logauth("CHANGE SESSION IP: %s(previus) -> %s(current)", $sess->{ip}, $ip);
        return errno => 'ipchg', @r;
    }
    
    # если мы сказали сессии "давай-досвидания" (зашли под другой сессией)
    # То надо сообщить об этом и удалить сессию
    if (my $closed = $sess->{closed}) {
        logauth("SESSION CLOSED BY OTHER: reason=%s", $closed);
        return errno => $closed, @r;
    }
    
    # Превышено время сессии
    my $time;
    if (($sess->{expiremax} > 0) && ($sess->{expiremax} <= ($time||=time))) {
        # Максимальное время сессии проверяем сначала,
        # т.к. время idle не может его перепрыгнуть
        logauth("SESSION EXPIRED MAX: %s", Clib::DT::fromtime($sess->{expiremax}));
        return errno => 'sexpmax', @r;
    }
    if (($sess->{expire} > 0) && ($sess->{expire} <= ($time||=time))) {
        logauth("SESSION EXPIRED MAX: %s", Clib::DT::fromtime($sess->{expire}));
        return errno => 'sexpire', @r;
    }
    
    # Ищем пользователя
    my $user = sqlGet(admin => $sess->{uid});
    if (!$user) {
        logauth("SESSION UNKNOWN UID=%s", $sess->{uid});
        return errno => 'sessinf', @r;
    }
    
    # Пароль пустой - глобальный запрет доступа
    if ($user->{password} eq '') {
        logauth("SESSION Empty password on user: %s", $user->{login});
        return errno => 'rdenied', @r;
    }
    
    my $grp = $user->{gid} ? sqlGet(admgrp => $user->{gid}) : {};
    
    if (!$grp) {
        logauth("SESSION UNKNOWN GID=%s", $user->{gid});
        return errno => 'ugroup', @r;
    }
    
    # Проверка прав доступа
    my $acc = $user->{$accf};
    if ($acc && ($acc eq 'grp')) {
        $acc = $grp->{$accf};
    }
    if (!$acc) {
        logauth("SESSION Access denied for user: %s", $user->{login});
        return errno => 'accdenied', @r;
    }
    
    # Если указано, обновляем время посещения
    my @upd = ( visit => Clib::DT::fromtime($time||=time) );
    if ($sess->{expire} > 0) {
        # Необходимо продлить сессию дальше
        my $expire = $user->{sessidle} || $user->{group}->{sessidle} || c(session => 'idle') || -1;
        if ($expire <= 0) {
            push @upd, expire => 0;
        }
        else {
            $expire += $time||=time;
            $expire = $sess->{expiremax} if ($sess->{expiremax} > 0) && ($expire > $sess->{expiremax});
            push(@upd, expire => $expire) if $sess->{expire} != $expire;
        }
    }
    
    if (@upd) {
        sqlUpd(session => $sess->{id}, @upd)
            || return errno => 'sessupd', @r;
    }
    
    return
        @r,
        user    => $user,
        group   => $grp,
        acc     => $acc,
        isfull  => $acc eq 'full' ? 1 : 0;
}


1;
