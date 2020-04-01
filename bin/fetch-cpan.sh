#!/bin/bash

case "$1" in
    -h|--help)
        echo "Wrapper for bin/fetch-cpan"
        exit
    ;;
esac

DIR="$( dirname ${BASH_SOURCE[0]} )/.."
cd $DIR

./bin/fetch-cpan --data ~/obs-mirror

