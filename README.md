# cassandra-lucene 

## General

Cassandra docker image with the Stratio Cassandra Lucene Index plugin Installed. It is based on gcr.io/google-samples/cassandra:v12, which uses Cassandra 3.9.0, with the addition of the Stratio Cassandra Lucene Index plugin. This image is meant to be a a drop in replacement for gcr.io/google-samples/cassandra:v12 in the [Kubernetics Example: Deploying Cassandra with Stateful Sets](https://kubernetes.io/docs/tutorials/stateful-application/cassandra/).

The plugin was compiled as per the documentation in readme.rst on [https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0](https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0). 

## Testing/Demo

Use the test script: sh ./test_with_cqlsh.sh

The image is pretty minimal so it is a bit tricky to test as you cannot use the container's cqlsh. The test script uses cqlsh from the offical cassandra container to connect to the jeffharwell/cassandra image and create a test search on a small amount of sample data.

#### The Test

This is roughly what the test script is doing. You can run the following in cqlsh connected to a running jeffharwell/cassandra container to test it by hand. If you want to do this the [official Cassandra image](https://hub.docker.com/r/_/cassandra/) has some documentation that will be helpful.

This example comes from the [https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0](https://github.com/Stratio/cassandra-lucene-index/tree/3.9.0) readme.md with a few modifications. See that link for several more examples of the plugin in action.

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

