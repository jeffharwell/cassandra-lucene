#!/bin/bash

VERSION=`head -n 1 ./currentversion`
sudo ./build.sh
sudo docker run --env-file ./env.list -it --rm --entrypoint /bin/bash jeffharwell/cassandra:$VERSION
