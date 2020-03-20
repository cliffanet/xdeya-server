package CUser::_root;

use Clib::strict8;

sub _root :
        Simple
{
    WebUser::menu('device');
    
    return
        'devicelist';
}
        
1;
