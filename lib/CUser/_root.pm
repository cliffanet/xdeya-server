package CUser::_root;

use Clib::strict8;

sub _root :
        Simple
{
    my @dev = CUser::Device::allMy();
    
    return CUser::Device::_root($dev[0]) if @dev == 1;
    
    return CUser::Device::list(\@dev);
}
        
1;
