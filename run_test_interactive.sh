#!/bin/bash

VERSION=`head -n 1 ./currentversion`
sudo docker run --env-file ./env.list -d --rm --name cassandra-interactive jeffharwell/cassandra:${VERSION}
#sudo docker run -d --rm --name cassandra-interactive jeffharwell/cassandra:${VERSION}
sudo docker exec -it cassandra-interactive /bin/bash
sudo docker stop cassandra-interactive
