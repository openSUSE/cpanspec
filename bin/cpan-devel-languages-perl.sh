#!/bin/bash

DIR="$( dirname ${BASH_SOURCE[0]} )/.."
cd $DIR

./bin/fetch-cpan --data ~/obs-mirror

./bin/status --data ~/obs-mirror --project devel:languages:perl:CPAN- --update
