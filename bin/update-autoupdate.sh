#!/bin/bash

DIR="$( dirname ${BASH_SOURCE[0]} )/.."
cd $DIR

./bin/status-perl --data ~/obs-mirror --project devel:languages:perl:autoupdate --update

./bin/update-perl \
    --data ~/obs-mirror \
    --project devel:languages:perl:autoupdate \
    --max 20
