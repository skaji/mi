use 5.26.0;
package App::Mi 0.01;

use Dist::Milla::App;
use Getopt::Long ();
use Moose;
use Path::Tiny 'path';
use experimental 'signatures';

sub Path::Tiny::replace ($self, $sub) {
    local $_ = $self->slurp;
    $sub->();
    $self->spew($_);
}

sub milla   (@argv) { local @ARGV = @argv; state $app = Dist::Milla::App->new; $app->run }
sub _capture ($cmd) { chomp( my $s = `$cmd` ); $? == 0 or die "Failed $cmd\n"; $s }
sub _system (@argv) { !system @argv or die "Failed @argv\n" }

has dir         => (is => 'rw', default => sub { shift->module =~ s/::/-/gr }, lazy => 1);
has email       => (is => 'rw', default => sub { _capture "git config --global user.email" });
has github_host => (is => 'rw', default => sub { _capture "git config --global github.host" });
has github_user => (is => 'rw', default => sub { _capture "git config --global github.user" });
has module      => (is => 'rw');
has user        => (is => 'rw', default => sub { _capture "git config --global user.name" });
has xs          => (is => 'rw');

sub parse_options ($self, @argv) {
    my $parser = Getopt::Long::Parser->new(
        config => [qw(no_auto_abbrev no_ignore_case bundling)],
    );
    $parser->getoptionsfromarray(\@argv,
        "x|xs" => sub { $self->xs(1) },
        "h|help" => sub { print "Usage:\n  > mi Module\n  > mi --xs Module\n"; exit },
    ) or exit 1;
    my $module = shift @argv;
    $module = shift @argv if $module && $module eq "new";
    die "Missing module argument\n" unless $module;
    $module =~ s/-/::/g;
    $self->module($module);
    $self;
}

sub run ($class, @argv) {
    my $self = $class->new;
    $self->parse_options(@argv);

    milla "new", $self->module;
    chdir $self->dir or exit 1;

    unlink $_ for qw(t/basic.t);
    mkdir $_ for qw(script xt);

    $self->prepare_files;

    my $repo = sprintf 'ssh://git@%s/%s/%s.git', $self->github_host, $self->github_user, $self->dir;
    _system "git", "remote", "add", "origin", $repo;
    _system "git", "add", "--all";
    milla "build", "--no-tgz";
    milla "clean";
    _system "git", "add", ".";
}

sub prepare_files ($self) {
    path(".gitignore")->append(<<~'___');
    /.carmel/
    /MANIFEST
    /META.yml
    /Makefile
    /Makefile.old
    /blib/
    /cpanfile.snapshot
    /local/
    /pm_to_blib
    .DS_Store
    *.o
    *~
    lib/**/*.c
    /temp
    ___

    my $ini;
    if ($self->xs) {
        $ini = <<~'___';
        [@Milla]
        installer = ModuleBuild
        ModuleBuild.mb_class = MyBuilder
        ___
    } else {
        $ini = <<~'___';
        [@Milla]
        ModuleBuildTiny.static = yes
        ___
    }

    path("dist.ini")->spew(<<~"___");
    $ini
    [GitHubREADME::Badge]
    badges = travis
    ___

    my $travis;
    if ($self->xs) {
        $travis = "perl Build.PL && ./Build && PERL_DL_NONLAZY=1 prove -b t";
    } else {
        $travis = "prove -l t";
    }
    path(".travis.yml")->spew(<<~"___");
    language: perl
    sudo: false
    perl:
      - "5.8"
      - "5.10"
      - "5.12"
      - "5.14"
      - "5.16"
      - "5.18"
      - "5.20"
      - "5.22"
      - "5.24"
    install:
      - cpanm -nq --installdeps --with-develop .
    script:
      - $travis
    ___

    path("cpanfile")->spew("requires 'perl', '5.008001';\n");
    path("cpanfile")->append("\n" . <<~'___') if $self->xs;
    on test => sub {
        requires 'Test::More', '0.98';
        requires 'Test::LeakTrace';
    };
    ___
    path("Changes")->replace(sub {
        s{^\s+-}{    -}smg;
    });

    my $email = $self->email;
    path( "lib/" . ($self->module =~ s{::}{/}gr) . ".pm" )->replace(sub {
        s{\Q'0.01'}{'0.001'};
        s{\nuse strict;\nuse 5.008_005;}{use strict;\nuse warnings;\n};
        s{=head1 SEE ALSO\n\n}{};
        s{\QE<lt>}{<}g; s{\QE<gt>}{>}g;
        s{=head1\s+LICENSE\n\n}{}x;
        s{head1 COPYRIGHT}{head1 COPYRIGHT AND LICENSE};
        s{Copyright (\d+)- ([^\n]+)}{Copyright $1 $2 <$email>};
    });
    path("t/00_use.t")->spew(<<~"___");
    use strict;
    use warnings;
    use Test::More tests => 1;
    use @{[ $self->module ]};
    pass "happy hacking!";
    ___
    path("t/01_leak.t")->spew(<<~"___") if $self->xs;
    use strict;
    use warnings;
    use Test::More;
    use Test::LeakTrace;
    use @{[ $self->module ]};

    no_leaks_ok {
        # TODO
    };

    done_testing;
    ___

    $self->write_xs_files if $self->xs;
}

sub write_xs_files ($self) {
    my $path = $self->module;
    $path =~ s{::}{/}g;
    $path = "lib/$path";

    my $load = <<~'___';
    use XSLoader;
    XSLoader::load(__PACKAGE__, $VERSION);
    ___
    path("$path.pm")->replace(sub {
        s{1;\n}{$load\n1;\n};
    });

    path("$path.xs")->spew(<<~"___");
    #ifdef __cplusplus
    extern "C" {
    #endif

    #define PERL_NO_GET_CONTEXT /* we want efficiency */
    #include <EXTERN.h>
    #include <perl.h>
    #include <XSUB.h>

    #ifdef __cplusplus
    } /* extern "C" */
    #endif

    #define NEED_newSVpvn_flags
    #include "ppport.h"

    MODULE = @{[ $self->module ]}  PACKAGE = @{[ $self->module ]}

    PROTOTYPES: DISABLE

    void
    hello()
    CODE:
    {
      SV* const hello = sv_2mortal(newSVpv("hello", 5));
      XPUSHs(hello);
      XSRETURN(1);
    }
    ___
    # / workaround PPI https://github.com/adamkennedy/PPI/issues/203

    my $dirname = path($path)->dirname;
    require Devel::PPPort;
    Devel::PPPort::WriteFile("$dirname/ppport.h");

    mkdir "inc";
    path("inc/MyBuilder.pm")->spew(<<~'___');
    package MyBuilder;
    use strict;
    use warnings;
    use base 'Module::Build';

    sub new {
        my $class = shift;
        $class->SUPER::new(
            # c_source => [],
            # include_dirs => [],
            # extra_compiler_flags => [], # -xc++ for c++
            # extra_linker_flags => [],   # -lstdc++ for c++
            @_,
        );
    }

    1;
    ___
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Mi - my personal favorite for milla new

=head1 SYNOPSIS

  > mi Module
  > mi --xs Module

=head1 INSTALL

If you have L<cpm>, then

  > cpm install -g git://github.com/skaji/mi.git

Otherwise

  > cpanm -nq git://github.com/skaji/mi.git

=head1 SETUP

  # prepare ~/.dzil/config.ini
  > dzil setup

  # set some info in ~/.gitconfig
  > git config --global user.name 'Shoichi Kaji'
  > git config --global user.email 'skaji@cpan.org'
  > git config --global github.host github.com  # change this if you use GHE
  > git config --global github.host skaji

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
