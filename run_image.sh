#!/bin/bash

sudo docker run -d --rm --name cassandra jeffharwell/cassandra:v12

IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cassandra`
echo "The Docker Cassandra container is available at IP ${IP}"
echo "To stop and remove the container run:"
echo "sudo docker stop cassandra"

