#!/bin/bash

echo "Starting Cassandra with Stratio Cassandra Lucene Index"
sudo docker run -d --rm --name cassandra jeffharwell/cassandra:3.11.3.0v3

echo "Waiting 30 seconds for Cassandra to start"
echo "If you get a 'Unable to connect to any servers' message you may need to lengthen this timeout."
sleep 30 

## This example code is derived from the examples in the readme.md of the Stratio Cassandra Lucene
## Index github repository.
## 
## https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0

echo "Starting cqlsh container"
sudo docker run -it --name cqlsh --link cassandra:cassandra --rm cassandra:3.11 sh -c "exec cqlsh cassandra <<EOF
    -- create the keyspace and the table
    CREATE KEYSPACE demo 
    WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1}; 
    USE demo; 
    CREATE TABLE tweets ( 
       id INT PRIMARY KEY, 
       user TEXT, 
       body TEXT, 
       message TEXT,
       time TIMESTAMP, 
       latitude FLOAT, 
       longitude FLOAT 
    ); 

    -- create the Lucene index
    CREATE CUSTOM INDEX tweets_index ON tweets ()
    USING 'com.stratio.cassandra.lucene.Index'
    WITH OPTIONS = {
       'refresh_seconds': '1',
       'schema': '{
          fields: {
             id: {type: \"integer\"},
             user: {type: \"string\"},
             body: {type: \"text\", analyzer: \"english\"},
             message: {type: \"text\", analyzer: \"english\"},
             time: {type: \"date\", pattern: \"yyyy/MM/dd\"},
             place: {type: \"geo_point\", latitude: \"latitude\", longitude: \"longitude\"}
          }
       }'
    };

    -- insert some data
    insert into tweets (id, body, message) values (1, 'include this', 'if you see this message');
    insert into tweets (id, body, message) values (2, 'include this', 'and only this message');
    insert into tweets (id, body, message) values (3, 'not this', 'IT DID NOT WORK');
    insert into tweets (id, body, message) values (4, 'include this', 'then the test worked');
    insert into tweets (id, body, message) values (5, 'not this', 'IT DID NOT WORK');

    -- Explicitly refresh all the indicies to index the new data
    CONSISTENCY ALL
    SELECT * FROM tweets WHERE expr(tweets_index, '{refresh:true}');
    CONSISTENCY QUORUM

    -- run the select using the index
    SELECT message FROM tweets WHERE expr(tweets_index, '{
       query: {type: \"phrase\", field: \"body\", value: \"include this\", slop: 1}
       }') LIMIT 100;
EOF
"

echo "Stopping Cassandra and deleting container"
sudo docker stop cassandra

