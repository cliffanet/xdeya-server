package CUser::Auth;

use Clib::strict8;

use Clib::DB::MySQL 'DB';
use Clib::Web::Controller;

use Encode;
use Digest::MD5 qw(md5_hex);
use utf8;

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
    
    my $code = 'ds3ax6fs';
    
    return 'md51:'.md5_hex($pass, $code);
}

sub login :
        AllowNoAuth
        Title('Авторизация (выполнение)')
        ReturnOperation
{
    my $p = wparam();
    my $email    = $p->str('email');
    my $password = $p->raw('p');
    $password = '' if !defined($password);
    
    my @err = ();
    
    # Проверка логина
    if ($email eq '') {
        logauth("AUTH: Empty email");
        return err => c(state => loginerr => 'empty'), @err;
    }
    
    # Хорошо бы передавать логин через msg, чтобы в случае редиректа он уже был автоматически введён,
    # однако, если будет ошибка авторизации (например, при подборе пароля), то каждый раз
    # будет создаваться сессия с сохранённым логином, которая не будет стираться до таймаута,
    # пока не будет открыта страница. При ajax-авторизации такое, например, вообще штатно происходит.
    # Поэтому, чтобы не делать лишних сохранений в БД и вообще лишних действий, сохранять логин не будем
    #push @err, login => $login;
    
    # Проверяем существование аккаунта
    my $user = sqlGet(user => email => $email);
    
    if (!$user || !$user->{id}) {
        logauth("AUTH: Unknown user: %s", $email);
        return err => c(state => loginerr => 'wrong'), @err;
    }
    
    # Проверяем пароль
    if ($user->{password} eq '') {
        # Пароль пустой - глобальный запрет доступа
        logauth("AUTH: Empty password on user: %s", $email);
        return err => c(state => loginerr => 'wrong'), @err;
    }
    
    if ($user->{password} =~ /^md51\:[0-9a-f]+$/) {
        # Новый md51-формат
        my $pass = passenc($password);
        if ($user->{password} ne $pass) {
            logauth("AUTH: Failed for user: %s", $email);
            return err => c(state => loginerr => 'wrong'), @err;
        }
    }
    else {
        logauth("AUTH: Unknown password-format for user: %s (%s)", $email, $user->{password});
        return err => c(state => loginerr => 'wrong'), @err;
    }
    
    logauth("AUTH: Succeful for user: %s (%s)", $email, $user->{login});
    
    # Создаем новую сессию
    my $sid = sessnew(uid => $user->{id})
        || return err => c(state => loginerr => 'sessadd'), @err;
    WebUser::login(user => $user);
    
    return ok => c(state => 'loginok'), redirect => '/';
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

sub sessnew {
    my %p = @_;
    
    my $time = time;
    
    my $skey = int(rand(0xFFFFFFFF));
    my @sess = (
        key     => $skey,
        ip      => $ENV{REMOTE_ADDR} || '',
        dtbeg   => Clib::DT::now(),
        dtact   => Clib::DT::now(),
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

sub sesscheck {
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
    
    # Ищем пользователя
    my $user = sqlGet(user => $sess->{uid});
    if (!$user) {
        logauth("SESSION UNKNOWN UID=%s", $sess->{uid});
        return errno => 'sessinf', @r;
    }
    
    # Пароль пустой - глобальный запрет доступа
    if ($user->{password} eq '') {
        logauth("SESSION Empty password on user: %s", $user->{login});
        return errno => 'rdenied', @r;
    }
    
    # обновляем время посещения
    sqlUpd(session => $sess->{id}, dtact => Clib::DT::now())
        || return errno => 'sessupd', @r;
    
    return
        @r,
        user    => $user;
}



sub regform :
        AllowNoAuth
        Title('Регистрация нового аккаунта')
        ReturnBlank
{
    my @p = ();
    my $p = wparam();
    
    
    return 'auth_register';
}

sub register :
        AllowNoAuth
        Title('Авторизация (выполнение)')
        ReturnOperation
{
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    
    # email
    my $email = $p->str('email');
    if ($email eq '') {
        logauth('REG: `email` empty');
        push @ferr, email => 'empty';
    }
    elsif ($email !~ /^[a-zA-Z][a-zA-Z\d\.\-\_]+\@([a-zA-Z\d\-\_]+\.)+[a-zA-Z]+$/) {
        logauth('REG: `email` wrong format: %s', $email);
        push @ferr, email => 'format';
    }
    elsif (my ($user) = sqlSrch(user => email => $email)) {
        logauth('REG: `email` exists: %s', $email);
        push @ferr, email => 'emailexists';
    }
    
    # пароль
    my $password = $p->raw('p');
    $password = '' if !defined($password);
    if ($password eq '') {
        push @ferr, p => 'empty';
    }
    
    my $pass2 = $p->raw('p2');
    $pass2 = '' if !defined($pass2);
    if ($password ne $pass2) {
        push @ferr, p2 => 'passmatch';
    }
    
    # имя
    my $name = $p->str('name');
    if ($name eq '') {
        push @ferr, name => 'empty';
    }
    elsif ($name !~ /^[a-zA-Zа-яА-Я]{2,}/) {
        push @ferr, name => 'format';
    }
    
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # генерируем код подтверждения email
    my $confirm = '';
    my @symb = ('a' .. 'z', 'A' .. 'Z', '0' .. '9');
    my $n = rand(10) + 10;
    foreach (1 .. $n) {
        my $i = rand(scalar(@symb));
        $confirm .= $symb[$i];
    }
    
    # Пишем в базу
    my @user = (
        email   => $email,
        password=> passenc($password),
        name    => $name,
        confirm => $confirm,
        dtreg   => Clib::DT::now(),
    );
    my $uid = sqlAdd(user => @user) || return err => 'db';
    
    # Создаем новую сессию
    my $sid = sessnew(uid => $uid)
        || return err => c(state => loginerr => 'sessadd');
    WebUser::login(user => { id => $uid, @user });
    
    # Отправляем E-Mail со ссылкой на подтверждение
    _confirm_send()
        || return err => c(state => confirm => 'sendfail');
    
    # ок
    return ok => c(state => 'regok'), redirect => '/';
}

use Mail::Sender;
sub _confirm_send {
    my %auth = WebUser::auth();
    my $user = $auth{user} || return;
    my $email = $user->{email} || return;
    
    my $tmpl = WebUser::tmpl('auth_confirm') || return;
    
    my @p = (
        href_host   => c('href_host'),
        href_base   => WebUser::pref(''),
        auth        => \%auth,
    );
    
    my $html = $tmpl->html({ @_, @p });
    
    my $m = c('mail')||{};
    my $sender = Mail::Sender->new($m->{sender});
    if (!$sender) {
        error('Cant\'t init mail-module');
        return;
    }
    
    my $r = $sender->MailMsg({
        to => $email,
        encoding => 'base64',
        ctype => 'text/html; charset=UTF-8',
        subject => $m->{subject_confirm},
        msg => $html,
    });
    
    # Отправка
    if (!ref($r)) {
        error('E-mail send error: %s', $r);
        return;
    }
    
    1;
}

sub confsend :
        Title('Повторная отправка E-Mail для подтверждения')
        ReturnOperation
{
    my %auth = WebUser::auth();
    my $user = $auth{user} || return;
    
    $user->{confirm}
        || return err => c(state => confirm => 'noneed');
    
    _confirm_send()
        || return err => c(state => confirm => 'sendfail');
    
    return ok => c(state => confirm => 'sendok'), redirect => '';
}
        
sub confirm :
        Title('Повторная отправка E-Mail для подтверждения')
        ParamRegexp('[\da-zA-Z]+')
{
    my $confirm = shift;
    my %auth = WebUser::auth();
    my $user = $auth{user} || return;
    
    $user->{confirm}
        || return 'auth_doconfirm', err => c(state => confirm => 'noneed');
    if ($user->{confirm} ne $confirm) {
        return 'auth_doconfirm', err => c(state => confirm => 'notequal');
    }
    
    sqlUpd(user => $user->{id}, confirm => '')
        || return 'auth_doconfirm', err => c(state => std => 'db');
    
    $user->{confirm} = '';
    
    return 'auth_doconfirm', ok => 1;
}


1;
