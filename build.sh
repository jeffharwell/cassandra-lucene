#!/bin/bash

if [ 'root' != `whoami` ]; then
    echo "You must run this as root"
    exit 1
fi

VERSION=`head -n 1 ./currentversion`
docker build -t jeffharwell/cassandra-lucene:${VERSION} .
