requires 'perl', '5.14.0';

requires 'Dist::Milla';
requires 'Path::Tiny';

on test => sub {
    requires 'Test::More', '0.98';
};
