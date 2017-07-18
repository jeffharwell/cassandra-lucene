# cassandra

## General


Cassandra docker image with Stratio Lucene Plugin Installed it is based on gcr.io/google-samples/cassandra:v12, which uses Cassandra 3.9.0, and adds the (Stratio Cassandra Lucene Index plugin.

The plugin was compiled as per the documentation in the readme on [https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0](https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0). 

## Testing/Demo

Use the test script: sh ./test_with_cqlsh.sh

The image is pretty minimal so it is a bit tricky to test so you cannot use the container's cqlsh. The test script uses the cqlsh from the offical cassandra container to connect to the image jeffharwell/cassandra image and create a test search on a small amount of data.

#### The Test

This is roughly what the test script is doing. You can run the following in cqlsh connected to a running jeffharwell/cassandra container.

This example comes from the (https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0)[https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0] readme.md with a few modifications.

    CREATE KEYSPACE demo
    WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1};
    USE demo;
    CREATE TABLE tweets (
       id INT PRIMARY KEY,
       user TEXT,
       body TEXT,
       time TIMESTAMP,
       latitude FLOAT,
       longitude FLOAT
    );
    
    CREATE CUSTOM INDEX tweets_index ON tweets ()
    USING 'com.stratio.cassandra.lucene.Index'
    WITH OPTIONS = {
       'refresh_seconds': '1',
       'schema': '{
          fields: {
             id: {type: "integer"},
             user: {type: "string"},
             body: {type: "text", analyzer: "english"},
             time: {type: "date", pattern: "yyyy/MM/dd"},
             place: {type: "geo_point", latitude: "latitude", longitude: "longitude"}
          }
       }'
    };
    
    insert into tweets (id, body) values (1, 'this is a test');
    insert into tweets (id, body) values (2, 'this is also a test record');
    insert into tweets (id, body) values (3, 'this one does not use that word');

Now try the select (at least a second after inserting the data so the index has time to refresh)

    SELECT * FROM tweets WHERE expr(tweets_index, '{
       query: {type: "phrase", field: "body", value: "test", slop: 1}
       }') LIMIT 100;

You should get the followings results .. so pretty.

     id | body                       | latitude | longitude | time | user
    ----+----------------------------+----------+-----------+------+------
      1 |             this is a test |     null |      null | null | null
      2 | this is also a test record |     null |      null | null | null

