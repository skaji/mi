# NAME

App::Mi - my personal favorite for milla new

# SYNOPSIS

    > mi Module
    > mi --xs Module

# INSTALL

If you have [cpm](https://metacpan.org/pod/cpm), then

    > cpm install -g git://github.com/skaji/mi.git

Otherwise

    > cpanm -nq git://github.com/skaji/mi.git

# SETUP

    # prepare ~/.dzil/config.ini
    > dzil setup

    # set some info in ~/.gitconfig
    > git config --global user.name 'Shoichi Kaji'
    > git config --global user.email 'skaji@cpan.org'
    > git config --global github.host github.com  # change this if you use GHE
    > git config --global github.host skaji

# COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
