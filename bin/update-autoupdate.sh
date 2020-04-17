#!/bin/bash

case "$1" in
    -h|--help)
        echo "Wrapper for bin/status-perl && bin/update-perl"
        exit
    ;;
esac

DIR="$( dirname ${BASH_SOURCE[0]} )/.."
cd $DIR

./bin/status-perl --data ~/obs-mirror --project devel:languages:perl:autoupdate --update

./bin/update-perl \
    --data ~/obs-mirror \
    --project devel:languages:perl:autoupdate \
    --max 20
