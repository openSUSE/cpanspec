#!/bin/bash

DIR="$( dirname ${BASH_SOURCE[0]} )/.."
cd $DIR

./bin/fetch-cpan --data ~/obs-mirror

