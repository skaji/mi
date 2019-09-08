use 5.30.0;
package App::Mi 0.01;

use Capture::Tiny 'capture';
use Dist::Milla::App;
use File::Spec;
use File::pushd 'pushd';
use Getopt::Long ();
use Moose;
use Path::Tiny 'path';
use experimental 'signatures';

my $HELP = <<~'___';
Usage: mi [options] Module
 -x, --xs       create XS module
 -h, --help     show this help
 -v, --verbose  make mi verbose
___

sub Path::Tiny::replace ($self, $sub) {
    local $_ = $self->slurp;
    $sub->();
    $self->spew($_);
}

sub _capture ($cmd) { chomp( my $s = `$cmd` ); $? == 0 or die "Failed $cmd\n"; $s }
sub _system (@argv) { !system @argv or die "Failed @argv\n" }

has milla       => (is => 'rw', default => sub { Dist::Milla::App->new });
has dir         => (is => 'rw', default => sub { shift->module =~ s/::/-/gr }, lazy => 1);
has email       => (is => 'rw', default => sub { _capture "git config --global user.email" });
has github_host => (is => 'rw', default => sub { _capture "git config --global github.host" });
has github_user => (is => 'rw', default => sub { _capture "git config --global github.user" });
has module      => (is => 'rw');
has user        => (is => 'rw', default => sub { _capture "git config --global user.name" });
has xs          => (is => 'rw');
has verbose     => (is => 'rw');

sub milla_run ($self, @argv) {
    local @ARGV = @argv;
    $self->verbose ? $self->milla->run : capture { $self->milla->run };
}

sub parse_options ($self, @argv) {
    my $parser = Getopt::Long::Parser->new(
        config => [qw(no_auto_abbrev no_ignore_case bundling)],
    );
    $parser->getoptionsfromarray(\@argv,
        "x|xs" => sub { $self->xs(1) },
        "h|help" => sub { print $HELP; exit },
        "v|verbose" => sub { $self->verbose(1) },
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

    $self->milla_run(new => $self->module);
    my $guard = pushd $self->dir;

    unlink $_ for qw(t/basic.t);
    mkdir $_ for qw(script xt);

    $self->prepare_files;

    my $repo = sprintf 'ssh://git@%s/%s/%s.git', $self->github_host, $self->github_user, $self->dir;
    _system "git", "remote", "add", "origin", $repo;
    _system "git", "add", "--all";
    $self->milla_run("build", "--no-tgz");
    $self->milla_run("clean");
    _system "git", "add", ".";
    warn "Successfully created @{[$self->dir]}\n" unless $self->verbose;
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

        [MetaProvides::Package]
        inherit_version = 0
        inherit_missing = 0
        ___
    } else {
        $ini = <<~'___';
        [@Milla]

        [MetaProvides::Package]
        inherit_version = 0
        inherit_missing = 0
        ___
    }
    path("dist.ini")->spew($ini);

    my $workflow = path(".github/workflows/linux.yml");
    $workflow->parent->mkpath;
    my $test = $self->xs
             ? "perl Build.PL && ./Build && env PERL_DL_NONLAZY=1 prove -b t"
             : 'prove -l t';
    $workflow->spew(<<~"___");
    name: linux

    on:
      - push

    jobs:
      perl:

        runs-on: ubuntu-latest

        strategy:
          matrix:
            perl-version:
              - '5.8'
              - '5.10'
              - '5.16'
              - 'latest'

        container:
          image: perl:\${{ matrix.perl-version }}

        steps:
          - uses: actions/checkout\@v1
          - name: perl -V
            run: perl -V
          - name: Install Dependencies
            run: curl -fsSL --compressed https://git.io/cpm | perl - install -g --with-configure --with-develop --with-recommends
          - name: Run Tests
            run: $test
    ___

    path("cpanfile")->spew(<<~'___');
    requires 'perl', '5.008001';
    ___
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
    my $path = File::Spec->catfile("lib", $self->module =~ s{::}{/}gr);

    my $load = <<~'___';
    use XSLoader;
    XSLoader::load(__PACKAGE__, $VERSION);
    ___
    path("$path.pm")->replace(sub { s{1;\n}{$load\n1;\n} });
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
    hello(...)
    PPCODE:
    {
      if (items != 1) {
        croak("items != 1");
      }
      SV* name = ST(0);
      STRLEN name_len;
      const char* name_char = SvPV(name, name_len);
      // SV* hello = sv_2mortal(newSVpvn("hello ", 6));
      SV* hello = newSVpvn_flags("hello ", 6, SVs_TEMP);
      sv_catpvn(hello, name_char, name_len);
      XPUSHs(hello);
      XSRETURN(1);
    }
    ___

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
