package WebUser;

use Clib::strict8;
use Clib::Const;
use Clib::Log;
use Clib::Web::Controller;
use Clib::Web::Param;
use Clib::DB::MySQL 'DB';
use Clib::Template::Package;
use Clib::DT;

use JSON::XS;

$SIG{__DIE__} = sub { error('DIE: %s', $_) for @_ };

my $logpid = log_prefix($$);
my $logip = log_prefix('init');
my $loguser = log_prefix('');

my $href_prefix = '';
sub pref_short {
    my $href = webctrl_pref(@_);
    if (!defined($href)) {
        $href = '';
        #dumper 'pref undefined: ', \@_;
    }
    return $href;
}
sub pref { return $href_prefix . '/' . pref_short(@_); }

sub disp_search {
    my $href = shift() || return;
    
    if ($href_prefix ne '') {
        if (substr($href, 0, length($href_prefix)) ne $href_prefix) {
            return;
        }
        $href = substr($href, length($href_prefix), length($href)-length($href_prefix));
    }
    return webctrl_search($href);
}

webctrl_local(
        'CUser',
        attr => [qw/Title ReturnDebug ReturnJson ReturnOperation ReturnBlank ReturnSimple ReturnBlock AllowNoAuth/],
        eval => "
            use Clib::Const;
            use Clib::Log;
            use Clib::DB::MySQL;
            
            *wparam = sub { WebUser::param; };
            *user = sub { WebUser::user };
            *userid = sub { WebUser::userid };
            *json2data = sub { WebUser::json2data(\@_); };
        ",
    ) || die webctrl_error;

my $param;
sub param { $param ||= Clib::Web::Param::param(prepare => 1) }

my %auth = ();
sub auth { @_ ? $auth{shift()} : %auth };
sub user {
    my %auth = WebUser::auth();
    my $user = $auth{user} || return;
    $user->{id} || return;
    return $user;
}
sub userid {
    my $user = user() || return;
    return $user->{id};
}

my $menu = '';
sub menu {
    $menu = shift() if @_;
    return $menu;
}


sub login {
    while (@_) {
        my $key = shift;
        $auth{$key} = shift;
    }
}
sub logout {
    delete $auth{user};
    sessdel();
}
sub sessdel {
    my $sess = $auth{session} || return;
    
    sqlDel(session => $sess->{id});
    delete $auth{session};
    
    Clib::Web::Param::cookieset(sid => '', path => '/', delete => 1);
    Clib::Web::Param::cookieset(skey => '', path => '/', delete => 1);
}


sub json2data {
    my $json = shift();
    my $data = eval { JSON::XS->new->utf8->decode($json); };
    $data || error('JSON-decode fail: %s (%s)', $@, $json);
    return $data;
}


sub init {
    my %p = @_;
    
    $logpid->set($$);
    
    $href_prefix = $p{href_prefix} if $p{href_prefix};
}

sub request {
    my $path = shift;
    
    # Инициализация запроса
    Clib::DB::MySQL->logquery_disable;
    my $count = Clib::TimeCount->run();
    $logpid->set($$.'/'.$count);
    $logip->set($ENV{REMOTE_ADDR}||'-noip-');
    log('request %s', $path);

    # Авторизация
    %auth = CUser::Auth::sesscheck();
    
    if (my $user = $auth{user}) {
        $loguser->set($user->{login});
    }
    
    Clib::DB::MySQL->logquery_enable;
    
    # Проверка указанного запроса
    my ($disp, @disp) = webctrl_search($path);
    my $logdisp;
    if ($disp) {
        log('dispatcher found: %s (%s)', $disp->{symbol}, $disp->{path});
        #dumper 'disp: ', $disp;
        $logdisp = log_prefix($disp->{path});
    }
    else {
        $logdisp = log_prefix('-unknown dispatcher- ('.$path.')')
    }
    
    if (!$auth{user}) {
        # Сначала при отсутствующей авторизации проверяем, можем ли мы вообще работать по указанному url
        if (!$disp || !(grep { $_->[0] =~ /allownoauth/i } @{$disp->{attr}||[]})) {
            error("dispatcher not allowed whithout auth (redirect to /auth)");
            my $autherr = $auth{errno} || 'noauth';
            my @attr = map { $_->[0] } @{($disp||{})->{attr}||[]};
            if (grep { /return(operation|json)/i } @attr) {
                return return_operation(
                        #[$disp->{path}, @disp],
                        error       => c(state => loginerr => $autherr)||$autherr,
                        loginerr    => $autherr,
                        redirect    => 'auth',
                    );
            }
            elsif (grep { /return(simple|block)/i } @attr) {
                return '', undef, 'Content-type' => 'text/html; charset=utf-8';
            }
            else {
                my $url = redirect_url('auth');
                my $ar = pref_short($disp->{path}, @disp);
                if ($ar && ($ar ne 'auth')) {
                    $ar = '/' . $ar;
                    debug('auth-form redirect to: %s', $ar);
                    $url .= '?ar='.$ar;
                }
                return '', undef, Location => $url;
            }
        }
        
        # при проблемах с авторизацией надо так же разобраться с сессией, т.к. мы её не трогали,
        # чтобы дать разобраться с этим в return_operation
        sessdel();
    }
    
    # Теперь проверяем на 404
    if (!$disp) {
        error("dispatcher not found (redirect to /404)");
        #dumper \%ENV;
        return '', '404 Not found', 'Content-type' => 'text/plain', Pragma => 'no-cach';
    }
    
    # Выполняем обработчик
    my @web = ();
    {
        local $SIG{ALRM} = sub { error('Too long request do: %s (%s)', $disp->{path}, $path); };
        alarm(20);
        @web = webctrl_do($disp, @disp);
        alarm(0);
    }
    
    # Делаем вывод согласно типу возвращаемого ответа
    my %ret =
            map {
                my ($name, @p) = @$_;
                $name =~ /^return(.+)$/i ?
                    (lc($1) => [@p]) : ();
            }
            @{$disp->{attr}||[]};
        
    if ($ret{debug}) {
        require Data::Dumper;
        return
            join('',
                Data::Dumper->Dump(
                    [ $disp, \@disp, \@web, \%ENV, Clib::TimeCount->info],
                    [qw/ disp ARGS RETURN ENV RunCount RunTime /]
                )
            ),
            undef,
            'Content-type' => 'text/plain';
    }
    
    elsif ($ret{json})  {
        return return_json(@web);
    }
    
    elsif ($ret{operation})  {
        return return_operation(@web);
    }
    
    elsif ($ret{blank})  {
        return return_blank(@web);
    }
    
    elsif ($ret{simple})  {
        return return_simple(@web);
    }
    
    elsif ($ret{block})  {
        return return_block(@web);
    }
    
    else {
        return return_default(@web);
    };
}

sub clear {
    $logip->set('-clear-');
    $loguser->set('');
    %auth = ();
    undef $param;
    $menu = '';
    Clib::Web::Param::cookiebuild();
}

my $module_dir = c('template_module_dir');

if ($module_dir) {
    $module_dir = Clib::Proc::ROOT().'/'.$module_dir if $module_dir !~ /^\//;
}

my $proc;

sub tmpl_init {
    $proc && return $proc;
    
    my $log = log_prefix('Template::Package init');
    
    my %callback = (
        script_time     => \&Clib::TimeCount::interval,
        
        pref            => \&pref,
        #href_this       => sub {  },
        
        tmpl =>  sub {
            my $name = shift;
            my $tmpl = $proc->tmpl($name);
            if (!$tmpl) {
                error("tmpl('%s')> %s", $name, $proc->error());
            }
            return $tmpl;
        },
    );
    
    
    $proc = Clib::Template::Package->new(
        FILE_DIR    => Clib::Proc::ROOT().'/template',
        $module_dir ? (MODULE_DIR => $module_dir) : (),
        c('template_force_rebuild') ?
            (FORCE_REBUILD => 1) : (),
        USE_UTF8    => 1,
        CALLBACK    => \%callback,
        debug       => sub { debug(@_) }
    );
    
    if (!$proc) {
        error("on create obj: %s", $!||'-unknown-');
        return;
    }
    if (my $err = $proc->error) {
        undef $proc;
        error($err);
        return;
    };
    
    foreach my $plugin (qw/Base HTTP Block Misc/) {
        if (!$proc->plugin_add($plugin)) {
            undef $proc;
            error("plugin_add: %s", $proc->error);
            return;
        };
    }
    
    foreach my $parser (qw/Html/) {# jQuery/) {
        if (!$proc->parser_add($parser)) {
            undef $proc;
            error("parser_add: %s", $proc->error);
            return;
        };
    }
    
    $proc;
}

sub tmpl {
    $proc || tmpl_init() || return;
    
    my $tmpl = $proc->tmpl(@_);
    if (!$tmpl) {
        error("template(%s) compile: %s", $_[0], $proc->error);
        return;
    }
    
    return $tmpl;
}

sub return_html {
    my $base = shift;
    my $name = shift;
    my $block = shift;
    
    if (!$base && !$name) {
        return '', undef, 'Content-type' => 'text/html; charset=utf-8';
    }
    
    my $tmpl = $base ?
        tmpl($name, $base) :
        tmpl($name);
    $tmpl || return;
    
    my @p = ();
    if ($auth{user}) {
        push(@p,
            auth => \%auth,
        );
    }
    
    push(@p,
        href_base => pref(''),
        menu => $menu||'',
        ver => {
            original=> c('version'),
            full    => c('version') =~ /^(\d*\.\d)(\d*)([a-zA-Z])?$/ ? sprintf("%0.1f.%d%s", $1, $2 || 0, $3?'-'.$3:'') : c('version'),
            date    => Clib::DT::date(c('versionDate')),
        }
    );
    
    my $meth = 'html';
    $meth .= '_'.$block if $block;

    return
        $tmpl->$meth({ @_, @p, RUNCOUNT => Clib::TimeCount->count() }),
        undef,
        'Content-type' => 'text/html; charset=utf-8';
}

sub return_simple { return return_html('', shift(), '', @_); }

sub return_block { return return_html('', @_); }

sub return_default { return return_html('base', shift(), '', @_); }

sub return_blank { return return_html('base_blank', shift(), '', @_); }

sub return_json {
    my $json = eval { JSON::XS->new->pretty(0)->encode({ @_ }) };
    if (!$json) {
        error("return_json: %s", $@);
        return '', 403;
    }
    
    return $json, undef, 'Content-type' => 'application/json', Clib::Web::Param::cookiebuild();
}

sub return_operation {
    my %p = @_;
    
    # Ключ ok/err/error содержат текстовое сообщение о статусе выполненной операции
    # Могут сохранять либо сам текст, либо ключ стандартных сообщений
    foreach my $k (qw/ok err error/) {
        my $msg = $p{$k} || next;
        my $msg1 = c(state => std => $msg) || next;
        $p{$k} = $msg1;
    }
    
    # Ключ redirect содержит pref-массив, куда потом надо редиректить
    # В случае аякс-запроса, сформируется ссылка и будет передана в ответе
    my @pref = ref($p{redirect}) eq 'ARRAY' ? @{ $p{redirect} } :
                defined($p{redirect}) ? $p{redirect} : ();
    
    my $p = param();
    
    if ($p && $p->bool('ajax')) {
        my @json = ();
        if (my $msg = $p{ok}) {
            push @json, ok => 1, message => $msg;
            # В аякс-версии редирект используется только при успешном сообщении
            if ((@pref == 1) && ($pref[0] eq '')) {
                my $ref = redirect_referer();
                debug('return_operation: redirect to back %s', $ref);
                push(@json, redirect => $ref) if $ref;
            }
            elsif (@pref) {
                push(@json, redirect => pref(@pref));
            }
        }
        else {
            push @json, error => 1;
            if (my $err = $p{error} || $p{err}) {
                push @json, message => $err;
            }
            else {
                error("CRITICAL: return_operation whithout `ok` or `err`");
            }
            if (my $fld = $p{field}) {
                push @json, field => {
                    map { ( $_ => c(field => $fld->{$_}) || $fld->{$_} ) }
                    keys %$fld
                };
            }
        }
        
        #dumper('ajax return: ', @json);
        
        return return_json(@json);
    }
    
    return return_redirect(@pref);
}

sub redirect_referer {
    my $host = $ENV{HTTP_HOST} || return;
    
    if ($ENV{HTTP_REFERER} &&
        ($ENV{HTTP_REFERER} =~ /^https?\:\/\/([^\/]+)(\/.*)$/i) &&
        (lc($1) eq lc($host))) {
        return $2;
    }
    
    return;
}
sub redirect_url {
    # Простой редирект
    my $host = $ENV{HTTP_HOST};
    if (!$host) {
        error('redirect_url: $ENV{HTTP_HOST} not defined');
        return;
    }
    if (!@_) {
        error('redirect_url: params not defined');
        return;
    }
    my $href = pref(@_);
    
    return 'http://'.$ENV{HTTP_HOST}.$href;
}
sub return_redirect {
    # Обычный редирект
    my $host = $ENV{HTTP_HOST};
    if (!$host) {
        error('return_operation: $ENV{HTTP_HOST} not defined');
        return;
    }
    
    my $href;
    if (@_) {
        $href = pref(@_);
    }
    elsif (my $ref = redirect_referer()) {
        $href = $ref;
        debug('return_operation: redirect to back %s', $ref);
    }
    else {
        error('return_operation: redirect to back with wrong HTTP_REFERER: %s', $ENV{HTTP_REFERER});
        return;
    }
    
    return '', undef, Clib::Web::Param::cookiebuild(), Location => "http://".$ENV{HTTP_HOST}.$href;
}

1;
