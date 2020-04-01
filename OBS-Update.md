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
created manually. See below.

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

## Creating submit requests

Go to https://build.opensuse.org/project/show/devel:languages:perl:autoupdate
and click on the package you want to submit to devel:languages:perl.

Click on "link diff" to see the changes. This link might not be available
in every case (I don't know why). In that case click on the revisions to see
the changes.

If the build is passing and the diff looks ok, click on "Submit package".
The changes will automatically be filled in.
Check "Remove local package if request is accepted" and click on "Create".


## Example for updating just one module

    # Get newest modules from CPAN
    # It might take a while until a module is mirrored
    ./bin/fetch-cpan --data ~/obs-mirror

    # Update status which perl modules need to be updated
    ./bin/status-perl --data ~/obs-mirror --project devel:languages:perl:autoupdate --update

    # Update
    ./bin/update-perl --data ~/obs-mirror --project devel:languages:perl:autoupdate --package Mojolicious

Now go to
https://build.opensuse.org/package/show/devel:languages:perl:autoupdate/perl-Mojolicious
and create a Submit Request.

