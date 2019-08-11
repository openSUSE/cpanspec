#!/bin/bash

DIR="$( dirname ${BASH_SOURCE[0]} )/.."
cd $DIR

for LETTER in A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
do
    echo $LETTER
    ./bin/update \
        --data ~/obs-mirror \
        --project devel:languages:perl:CPAN- \
        --max 20 \
        $LETTER
done
