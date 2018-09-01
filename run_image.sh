#!/bin/bash

VERSION=`head -n 1 ./currentversion`
sudo docker run -d --rm --name cassandra jeffharwell/cassandra:${VERSION}

IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cassandra`
echo "The Docker Cassandra container is available at IP ${IP}"
echo "To stop and remove the container run:"
echo "sudo docker stop cassandra"

