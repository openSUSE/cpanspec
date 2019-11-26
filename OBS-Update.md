# Updating the perl modules repositories in OBS

There are a number of scripts that can update the following repositories:
* https://build.opensuse.org/project/show/devel:languages:perl:autoupdate
* https://build.opensuse.org/project/show/devel:languages:perl:CPAN-A (B, C, D
  etc.)

## Usage

This is how a crontab could look like:

    0 2 * * * $HOME/cpanspec/bin/fetch-cpan.sh > $HOME/obs-mirror/logs/cpan.log 2>&1
    0 3 * * * $HOME/cpanspec/bin/update-autoupdate.sh > $HOME/obs-mirror/logs/autoupdate.log 2>&1
    0 4 * * * $HOME/cpanspec/bin/update-dlp-cpan.sh > $HOME/obs-mirror/logs/cpanupdate.log 2>&1

First you need to create `~/obs-mirror` and `~/obs-mirror/logs`.

The `fetch-cpan.sh` will fetch the list of currently indexed modules from CPAN.

`update-autoupdate.sh` will update the
[autoupdate](https://build.opensuse.org/project/show/devel:languages:perl:autoupdate)
repository. It will branch projects from
[`devel:languages:perl`](https://build.opensuse.org/project/show/devel:languages:perl)
and build the newest version from CPAN.

Requests for submitting the new versions into `devel:languages:perl` have to be
created manually.

`update-dlp-cpan.sh` will update the `CPAN-A`, B, C repositories.

To get the current status you can use these commands:

    ./bin/status-perl --project devel:languages:perl:autoupdate --data ~/obs-mirror

This will show how many modules in `devel:languages:perl` are outdated.

    ./bin/status --data ~/obs-mirror --project devel:languages:perl:CPAN-  [W]

the same for the `CPAN-A`, B, C repositories.

## Exclude certain modules

Some modules can't be updated automatically via this script for different
reasons.
To prevent them from showing up in `autoupdate`, you can remove them and set the
status from `todo` to `error` in `~/obs-mirror/status/perl.tsv`. For example,
the latest Nagios::Plugin release is just a placeholder to say that there will
be no more releases, so `perl.tsv` contains:

    Nagios-Plugin\terror\t...

## Usage of update scripts

You can run the `bin/update` and `bin/update-perl` scripts with certain
options:

    --max 150

This will end the script after 150 updates

    --ask

This will prompt for every module if you want to update it

    --ask-commit

This will generate the spec, but ask before committing

## Cache

For the `CPAN-<letter>` projects there is a cache in:
`~/obs-mirror/obs-cache/`

It caches the versions that are already in OBS, because the returned
version via the OBS API is not reliable. The format is Perl Storable.

If you are moving this project to a different server or directory, you should
keep the cache directory, becase refilling the cache can take days and will
do a lot of API requests.
