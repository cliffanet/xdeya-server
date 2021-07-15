package CUser::WiFi;

use Clib::strict8;

sub byId {
    sqlGet(wifi => shift());
}

sub wifiBySsid {
    my ($dev, $ssid, $wifiid) = @_;
    return sqlSrch(
        wifi =>
        uid     => $dev->{uid},
        devid   => $dev->{id},
        ssid    => $ssid,
        @_ == 3 ? sqlNotEq(id => $wifiid) : ()
    );
}

sub _root :
        ParamCodeUInt(\&CUser::Device::byIdMy)
{
    WebUser::menu('device');
    my $dev = shift() || return 'notfound';
    
    my @list = sqlSrch(wifi => uid => $dev->{uid}, devid => $dev->{id}, sqlOrder('ssid'));
    
    return
        'wifilist',
        dev => $dev,
        list => \@list;
}

sub add :
        Title('Добавление Wifi-сети')
        ParamCodeUInt(\&CUser::Device::byIdMy)
        ReturnOperation
{
    my $dev = shift() || return err => 'notfound';
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    
    # имя
    my $ssid = $p->str('ssid');
    if ($ssid eq '') {
        push @ferr, ssid => 'empty';
    }
    elsif ($ssid =~ /[\r\n\t\000]/) {
        push @ferr, ssid => 'format';
    }
    elsif (wifiBySsid($dev, $ssid)) {
        push @ferr, ssid => 'duplicate';
    }
    
    # пароль
    my $pass = $p->raw('pass');
    if ($pass eq '') {
        push @ferr, pass => 'empty';
    }
    elsif ($pass =~ /[\r\n\t\000]/) {
        push @ferr, pass => 'format';
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    
    # Добавляем в базу
    my $wid = sqlAdd(
        wifi =>
        uid     => $dev->{uid},
        devid   => $dev->{id},
        ssid    => $ssid,
        pass    => $pass,
    ) || return err => 'db';
    
    if ($dev->{ckswifi}) {
        sqlUpd(device => $dev->{id}, ckswifi => '')
            || return err => 'db';
    }
    
    return ok => c(state => wifi => 'addok'), redirect => ['wifi' => $dev->{id}];
}

sub set :
        Title('Изменение Wifi-сети')
        ParamCodeUInt(\&CUser::Device::byIdMy)
        ParamCodeUInt(\&byId)
        ReturnOperation
{
    my $dev = shift() || return err => 'notfound';
    my $w = shift() || return err => 'notfound';
    return(err => 'notfound') if $w->{devid} != $dev->{id};
    my $p = wparam();
    
    # Проверяем поля
    my @ferr = ();
    my @upd = ();
    
    # имя
    if ($p->exists('ssid')) {
        my $ssid = $p->str('ssid');
        if ($ssid eq '') {
            push @ferr, ssid => 'empty';
        }
        elsif ($ssid =~ /[\r\n\t\000]/) {
            push @ferr, ssid => 'format';
        }
        elsif (wifiBySsid($dev, $ssid, $w->{id})) {
            push @ferr, ssid => 'duplicate';
        }
        push(@upd, ssid => $ssid) if $ssid ne $w->{ssid};
    }
    
    # пароль
    if ($p->exists('pass')) {
        my $pass = $p->raw('pass');
        if ($pass eq '') {
            push @ferr, pass => 'empty';
        }
        elsif ($pass =~ /[\r\n\t\000]/) {
            push @ferr, pass => 'format';
        }
        push(@upd, pass => $pass) if $pass ne $w->{pass};
    }
    
    # ошибки ввода данных
    if (@ferr) {
        return err => 'input', field => { @ferr };
    }
    @upd || return err => 'nochange';
    
    sqlUpd(wifi => $w->{id}, @upd)
        || return err => 'db';
    
    if ($dev->{ckswifi}) {
        sqlUpd(device => $dev->{id}, ckswifi => '')
            || return err => 'db';
    }
    
    return ok => c(state => wifi => 'setok'), redirect => ['wifi' => $dev->{id}];
}

sub del :
        Title('Удаление Wifi-сети')
        ParamCodeUInt(\&CUser::Device::byIdMy)
        ParamCodeUInt(\&byId)
        ReturnOperation
{
    my $dev = shift() || return err => 'notfound';
    my $w = shift() || return err => 'notfound';
    return(err => 'notfound') if $w->{devid} != $dev->{id};
    
    sqlDel(wifi => $w->{id})
        || return err => 'db';
    
    if ($dev->{ckswifi}) {
        sqlUpd(device => $dev->{id}, ckswifi => '')
            || return err => 'db';
    }
    
    return ok => c(state => wifi => 'delok'), redirect => ['wifi' => $dev->{id}];
}

        
1;
