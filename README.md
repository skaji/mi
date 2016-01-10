# mi [![Build Status](https://travis-ci.org/shoichikaji/mi.svg?branch=master)](https://travis-ci.org/shoichikaji/mi)

mi generates a project skeleton for creating a cpan module.

Actually mi is just a wrapper for
[Dist::Milla](https://github.com/miyagawa/Dist-Milla)'s `new` command.

Notable change is that mi does **NOT** generate README.md from Module.pod.

I think

* README.md should be for people who are **not** familiar with perl
* Module.pod should be for people who are familiar with perl

So, we should manage them separately.

## Install

Make sure you have [cpanm](https://github.com/miyagawa/cpanminus).
If not, install it first:

```sh
$ curl -sL http://cpanmin.us | perl - -nq App::cpanminus
```

Then:

```sh
$ cpanm -nq git://github.com/shoichikaji/mi.git
```

## Usage

```sh
$ mi Your::Module
$ cd Your-Module
$ vim lib/Your/Module.pm  # hack hack hack!
```

## License

Copyright (c) 2016 Shoichi Kaji

This software is licensed under the same terms as Perl.
