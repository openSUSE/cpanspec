#!/usr/bin/env bash

# Writes OBS build statistics to YAML files

# crontab example:
# 51,11,31 * * * *       STAT_DIR=$HOME/munin/obs-cpan BUILD_STATUS=/path/to/cpanspec/bin/build-status /path/to/build-status-cron.sh >>$HOME/munin/build-status-cron.log 2>&1

#STAT_DIR=$HOME/munin/obs-cpan
#BUILD_STATUS=$HOME/develop/github/cpanspec/bin/build-status

if [[ -z "$STAT_DIR" ]]; then
    echo "Set STAT_DIR=~/path/to/stats" >&2
    exit 1
fi
if [[ -z "$BUILD_STATUS" ]]; then
    echo "Set BUILD_STATUS=/path/to/cpanspec/bin/build-status" >&2
    exit 1
fi


[[ ! -d $STAT_DIR ]] && mkdir $STAT_DIR

cd $STAT_DIR

for LETTER in A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
    $BUILD_STATUS \
        --project-prefix devel:languages:perl:CPAN- --yaml "$LETTER" \
        >/tmp/build-status.yaml \
        && mv /tmp/build-status.yaml $STAT_DIR/build-status-$LETTER.yaml
    sleep 1
done

$BUILD_STATUS \
    --project devel:languages:perl --yaml perl \
    >/tmp/build-status.yaml \
    && mv /tmp/build-status.yaml $STAT_DIR/build-status-perl.yaml

$BUILD_STATUS \
    --project devel:languages:perl:autoupdate --yaml autoupdate \
    --repo standard \
    >/tmp/build-status.yaml \
    && mv /tmp/build-status.yaml $STAT_DIR/build-status-autoupdate.yaml
