package App::Mi;
use 5.14.0;
use warnings;

our $VERSION = '0.01';
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case bundling);
use Moose;
use Dist::Milla::App;

sub milla { local @ARGV = @_; state $app = Dist::Milla::App->new; $app->run }
sub _capture { chomp( my $s = `$_[0]` ); $? == 0 or die "Failed $_[0]\n"; $s }
sub _system { return !system @_ }

has user  => (is => 'rw', default => sub { _capture "git config --global user.name" });
has email => (is => 'rw', default => sub { _capture "git config --global user.email" });
has github_user => (is => 'rw', default => sub { _capture "git config --global github.user" });
has github_host => (is => 'rw', default => sub { _capture "git config --global github.host" });

has xs     => (is => 'rw');
has module => (is => 'rw');
has dir    => (is => 'rw', default => sub { shift->module =~ s/::/-/gr }, lazy => 1);

sub parse_options {
    my $self = shift;
    local @ARGV = @_;
    GetOptions
        "x|xs" => sub { $self->xs(1) },
        "h|help" => sub { print "Usage:\n  > mi Module\n  > mi --xs Module\n"; exit },
    or exit 1;
    my $module = shift @ARGV;
    $module = shift @ARGV if $module && $module eq "new";
    die "Missing module argument\n" unless $module;
    $module =~ s/-/::/g;
    $self->module($module);
    $self;
}

sub run {
    my $self = shift;
    milla "new", $self->module;
    chdir $self->dir or exit 1;

    unlink $_ for qw(Build.PL t/basic.t);
    mkdir $_ for qw(script xt);

    $self->prepare_files;

    my $repo = sprintf 'ssh://git@%s/%s/%s.git',
        $self->github_host, $self->github_user, $self->dir;
    _system "git remote add origin $repo" or exit 1;
    _system "git add --all" or exit 1;
    milla "build", "--no-tgz";
    milla "clean";
    _system "git add ." or exit;
}

use Path::Tiny;
package Path::Tiny {
    sub replace {
        my ($self, $sub) = @_;
        local $_ = $self->slurp;
        $sub->();
        $self->spew($_);
        $self;
    }
}

sub here ($) {
    my $str = shift;
    $str =~ s/[ ]+\z//;
    $str =~ s/\A[ ]*\n([ ]*)//;
    my $space = $1;
    $str =~ s/^$space//msg;
    $str;
}

sub prepare_files {
    my $self = shift;

    path(".gitignore")->append(here q(
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
        *.c
    ));

    my $ini;
    if ($self->xs) {
        $ini = here q(
            [@Milla]
            installer = ModuleBuild
            ModuleBuild.mb_class = MyBuilder
        );
    } else {
        $ini = here q(
            [@Milla]
            installer = MakeMaker

            [Metadata]
            x_static_install = 1
        );
    }

    path("dist.ini")->spew(here qq(
        name = @{[ $self->dir ]}

        $ini
        [GitHubREADME::Badge]
        badges = travis
    ));

    path(".travis.yml")->spew(here q(
        language: perl
        sudo: false
        perl:
          - "5.22"
          - "5.20"
          - "5.18"
          - "5.16"
          - "5.14"
          - "5.12"
          - "5.10"
          - "5.8"
    ));

    path("cpanfile")->spew(here qq(
        requires 'perl', '5.008005';

        on test => sub {
            requires 'Test::More', '0.98';
        };
    ));
    path("Changes")->replace(sub {
        s{^\s+-}{    -}smg;
    });

    my $email = $self->email;
    path( "lib/" . ($self->module =~ s{::}{/}gr) . ".pm" )->replace(sub {
        s{\nuse strict;\nuse 5.008_005;}{use strict;\nuse warnings;\n};
        s{=head1 SEE ALSO\n\n}{};
        s{\QE<lt>}{<}g; s{\QE<gt>}{>}g;
        s{= head1\s+LICENSE\n\n}{}x;
        s{head1 COPYRIGHT}{head1 COPYRIGHT AND LICENSE};
        s{Copyright (\d+)- ([^\n]+)}{Copyright $1 $2 <$email>};
    });
    path("t/00_use.t")->spew(here qq(
        use strict;
        use warnings;
        use Test::More;
        use @{[ $self->module ]};
        pass "happy hacking!";
        done_testing;
    ));

    $self->write_xs_files if $self->xs;
}

sub write_xs_files {
    my $self = shift;
    my $path = $self->module;
    $path =~ s{::}{/}g;
    $path = "lib/$path";

    my $load = here q(
        use XSLoader;
        XSLoader::load(__PACKAGE__, $VERSION);
    );
    path("$path.pm")->replace(sub {
        s{1;\n}{$load\n1;\n};
    });

    path("$path.xs")->spew(here qq(
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
    ));

    my $dirname = path($path)->dirname;
    require Devel::PPPort;
    Devel::PPPort::WriteFile("$dirname/ppport.h");

    mkdir "inc";
    path("inc/MyBuilder.pm")->spew(here q(
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
    ));
}


1;
__END__

=encoding utf-8

=head1 NAME

App::Mi - wrapper for milla new

=head1 SYNOPSIS

  > mi Module
  > mi --xs Module

=head1 INSTALL

  # static install!
  > cpanm-menlo -nq git://github.com/skaji/mi.git

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
