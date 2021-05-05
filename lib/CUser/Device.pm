package CUser::Device;

use Clib::strict8;
use Clib::BinProto;

use IO::Socket;

sub byId {
    sqlGet(device => shift());
}

sub byIdMy {
    my $user = user() || return;
    my $dev = byId(@_) || return;
    return if $dev->{uid} != $user->{id};
    return $dev;
}

sub allMy {
    my $user = user() || return;
    
    return sqlSrch(device => uid => $user->{id}, deleted => 0);
}

sub _root :
        ParamCodeUInt(\&byIdMy)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    
    my @jump = sqlSrch(jump => uid => $dev->{uid}, devid => $dev->{id}, sqlOrder('-id'));
    my @track= sqlSrch(track=> uid => $dev->{uid}, devid => $dev->{id}, sqlOrder('-id'));
    my @wifi = sqlSrch(wifi => uid => $dev->{uid}, devid => $dev->{id}, sqlOrder('ssid'));
    
    return
        'deviceinfo',
        dev => $dev,
        jump_list => \@jump,
        track_list=> \@track,
        wifi_list => \@wifi;
}

sub list :
        Title('Все устройства')
{
    my $user = user() || return;
    WebUser::menu('device');
    
    my $list = shift() || [ allMy() ];
    
    return
        'devicelist', list => $list;
}

sub add :
        Title('Добавление устройства')
        ReturnOperation
{
    my $user = user() || return;
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    
    # имя
    my $name = $p->str('name');
    if ($name eq '') {
        push @ferr, name => 'empty';
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Добавляем в базу
    my $devid = sqlAdd(
        device =>
        uid     => $user->{id},
        dtadd   => Clib::DT::now(),
        name    => $name,
    ) || return err => 'db';
    
    return ok => c(state => device => 'addok'), redirect => ['device/join' => $devid];
}

sub del :
        Title('Удаление устройства')
        ParamCodeUInt(\&byIdMy)
        ReturnOperation
{
    my $dev = shift() || return err => 'notfound';
    return(err => 'deleted') if $dev->{deleted};
    
    sqlDel(device => $dev->{id})
        || return err => 'db';
    
    return ok => c(state => device => 'delok'), redirect => 'device/list';
}

sub join :
        Title('Привязка устройства')
        ParamCodeUInt(\&byIdMy)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    return('notfound') if $dev->{deleted};
    
    if ($dev->{authid}) {
        sqlUpd(device => $dev->{id}, authid => 0);
    }
    
    
    return
        'devicejoin', dev => $dev;
}

sub joinfin :
        Title('Привязка устройства')
        ParamCodeUInt(\&byIdMy)
        ReturnOperation
{
    my $dev = shift() || return err => 'notfound';
    return(err => 'deleted') if $dev->{deleted};
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    
    # имя
    my $code = $p->str('code');
    if ($code eq '') {
        push @ferr, code => 'empty';
    }
    elsif ($code !~ /^[0-9a-fA-F]{4}$/) {
        push @ferr, code => 'format';
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Поключаемся к сокету
    my $updsock = c('sockjoin') || return err => 'system';
    $updsock = sprintf $updsock, hex($code);
    if (!(-e $updsock)) {
        error('Sock not found: %s', $updsock);
        return err => 'input', field => { code => 'joinfail' };
    }
    
    my $sock = IO::Socket::UNIX->new(
            Peer    => $updsock,
            Type    => SOCK_DGRAM
        );
    if (!$sock) {
        error('Sock(%s) connect fail: %s', $updsock, $!);
        return err => c(state => device => 'joinsend');
    }
    
    # инициируем binproto
    my $proto = Clib::BinProto->new(
        '#',
        { s => 0x13, code => 'join',      pk => 'NN',      key => 'authid,secnum' },
    ) ||  return err => 'system';
    
    # генерируем ключи
    my @d;
    while (1) {
        my $authid;
        @d = (
            authid => ($authid = int rand(0xffffffff)),
            secnum => int rand(0xffffffff),
            dtjoin => Clib::DT::now(),
        );
        sqlSrch(device => authid => $authid) || last;
    }
    
    # Обновляем в бд
    sqlUpd(device => $dev->{id}, @d)
        || return err => 'db';
    
    # и отправляем в устр-во
    $sock->send($proto->pack(join => { @d }))
        || return err => c(state => device => 'joinsend');
    
    return ok => c(state => device => 'joinok'), redirect => [device => $dev->{id}];
}
        
1;
