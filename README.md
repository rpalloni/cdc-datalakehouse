# cdc pipeline and data lakehouse

<img width="1853" height="480" alt="image" src="https://github.com/user-attachments/assets/852721c8-5492-49f6-9417-1630b7ef901c" />

Postgres > Kafka Connect (Debezium) > Kafka > Kafka Connect > Iceberg + Nessie + Minio <<< Dremio

## Connectors plugins initial setup 
[only once, takes 20 minutes] \
Activate docker server and run the scripts to download the connectors JARs in /custom-plugins repo:
* postgres: build the kafka connect jar files in custom-plugins with `bash scripts/debezium-jars-setup.sh` (https://debezium.io/releases/3.3/#installation > downloads > list of all connectors jars)
* iceberg: build the kafka connect jar files in custom-plugins with `bash scripts/iceberg-jars-setup.sh` (docs: https://iceberg.apache.org/docs/latest/kafka-connect/)

Once the connector repo is created, download additional Nessie jars in `/lib`: \
`cd custom-plugins/iceberg-connector-kafka/iceberg-kafka-connect-runtime-xxxxxxxxxx/lib`
```
curl -sL -o iceberg-nessie-1.7.1.jar https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-nessie/1.7.1/iceberg-nessie-1.7.1.jar
curl -sL -o nessie-model-0.99.0.jar https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie-model/0.99.0/nessie-model-0.99.0.jar
curl -sL -o nessie-client-0.99.0.jar https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie-client/0.99.0/nessie-client-0.99.0.jar
```
NOTE: use 0.99.0 — this is the version required by iceberg-nessie 1.7.1 (check iceberg-nessie pom)

## run
1 - `docker compose up --build`

Tools UIs:
* minio: http://localhost:9001/
* nessie: http://localhost:19120/
* dremio: http://localhost:9047/

2 - create bucket `warehouse` in minio (or uncomment the command in compose)

3 - register connectors via kafka connect api:
* `curl -i -X POST -H "Content-Type: application/json" http://localhost:8083/connectors --data "@configs/PostgresConnectorConfig.json"`
* `curl -i -X POST -H "Content-Type: application/json" http://localhost:8083/connectors --data "@configs/IcebergConnectorConfig.json"`

Useful API requests: \
`curl -X DELETE http://localhost:8083/connectors/iceberg-bookings-connector` \
`curl http://localhost:8083/connectors/iceberg-bookings-connector/config | jq .` \
`curl http://localhost:8083/connectors/iceberg-bookings-connector/status`

4 - generate postgres events:
```
CREATE TABLE public.bookings (
	id SERIAL PRIMARY KEY,
	booking_date DATE NOT NULL,
	service_id INT NOT NULL,
	quantity INT NOT NULL,
	total_amount NUMERIC(10, 2) NOT null,
	updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO public.bookings (booking_date, service_id, quantity, total_amount) values ('2023-01-01', 101, 3, 450.00);
INSERT INTO public.bookings (booking_date, service_id, quantity, total_amount) values ('2023-02-01', 102, 1, 320.00);
INSERT INTO public.bookings (booking_date, service_id, quantity, total_amount) values ('2023-03-01', 103, 4, 720.00);

UPDATE public.bookings SET total_amount = 350 WHERE id = 2;
DELETE FROM public.bookings WHERE id = 1;

SELECT * FROM public.bookings;
```

* While generating data monitor kafka streams: \
`docker compose exec kafka bash` \
`/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092` \
`/opt/kafka/bin/kafka-console-consumer.sh --topic postgres.public.bookings --partition 0 --offset earliest --bootstrap-server localhost:9092`

* Files available in the minio bucket with iceberg structure (data, metadata)


## Dremio UI
Accessing the iceberg tables with Dremio query engine

Configuration:
```
<General tab>
Name: nessie
Nessie Endpoint URL: http://nessie:19120/api/v2
Nessie Auth Type: none

<Storage tab>
AWS Root Path: warehouse # bucket in minio
Auth Type: AWS Access Key
AWS Access Key: admin
AWS Access Secret: password
IAM Role to Assume: 

Connection Properties:
* fs.s3a.endpoint: minio:9000
* fs.s3a.path.style.access: true
* fs.s3a.endpoint.region: eu-central-1 (Used by the Hadoop S3A filesystem driver)
* dremio.s3.compat: true
* dremio.s3.region: eu-central-1 (Explicitly sets the region for Dremio's S3 client)
- [ ] Uncheck “encrypt connection” 

------------

Connect directly the bucket
Name: minio
admin
password
[ ] enable compatibility mode
5 connection properties above
allowlist warehouse
```
##################################################################################################################################################################################################
### DREMIO NOTEs:
When you explicitly set a custom region like `eu-central-1` in MinIO, all downstream clients (Nessie and Dremio) must use that same region string.
This is because the S3 Signature Version 4 (SigV4) signing process uses the region name to generate the cryptographic signature; if there is a mismatch, MinIO will reject the request.


`DREMIO_JAVA_SERVER_EXTRA_OPTS=-Dpaths.dist=file:///opt/dremio/data/dist` \
`DREMIO_JAVA_SERVER_EXTRA_OPTS`: This is a Dremio-specific environment variable used to pass Java system properties (-D) specifically to the server process (the main Dremio engine). \
`-Dpaths.dist`: This overrides the paths.dist setting typically found in the dremio.conf file for dremio's internal workspace data \
`file:///opt/dremio/data/dist`: This tells Dremio to use a local file system path instead of a cloud storage bucket (like S3 or ADLS) for its distributed data.

```
/* DATA REFRESH
dremio does not detect automatically when iceberg connector commits a new snapshot causing stale metadata,
sometimes empty or with old rows depending on when the internal cache was last refreshed
=> force refresh to get the most recent metadata version
*/

ALTER TABLE nessie.db.bookings REFRESH METADATA; 
SELECT * FROM nessie.db.bookings;
```

```
/* VERSIONING
use versioning from UI on the table using main/branches and even specific commits SQL to create a branch and use it 
*/

CREATE BRANCH IF NOT EXISTS dev IN nessie;
INSERT INTO nessie.db.bookings at BRANCH dev (id, booking_date, service_id, quantity, total_amount, updated_at) 
VALUES (4, '2023-04-01', 104, 5, 20.00, CURRENT_TIMESTAMP);

SELECT * FROM nessie.db.bookings AT BRANCH main;
SELECT * FROM nessie.db.bookings AT BRANCH dev;
```


### POSTGRES NOTEs:
Storage engines represent data on disk and every WRITE is appended to log; this log can be exposed to other systems.

WAL (Write-Ahead Log) config: \
`wal_level=logical` enable replication needed by debezium connector for CDC.
`logical` decoding provides extra information allowing decoding of row-level INSERTs, UPDATEs, 
and DELETEs into structured *events* that Debezium connector can stream to Kafka topics.

REPLICATION ROLE config: \
database.user must have the REPLICATION role in Postgres for Debezium to be able to read the WAL.
The replication privilege is implicitly granted because POSTGRES_USER=docker is the superuser.                                                                         
When you use the POSTGRES_USER environment variable in the official postgres Docker image, that user is created as a superuser (SUPERUSER role), 
which includes REPLICATION automatically — no explicit GRANT is needed.                                                                                       
                                                                                                                                                          
So the chain is:                                                                                                                                        
- POSTGRES_USER=docker → created as superuser by the Docker entrypoint                                                                                  
- Superuser implicitly has REPLICATION privilege
- `wal_level=logical` enables WAL logical decoding
- Debezium connects as docker and can read the WAL stream

In production, where non-superuser account is used for Debezium, you'd need to explicitly grant it:
```
CREATE USER debezium WITH PASSWORD 'xyz' REPLICATION LOGIN;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO debezium;
```

### ICEBERG NOTEs: 
The Iceberg Sink Connector has two modes:
- Append (default): every Kafka message → new row added to Iceberg.
- Upsert: finds and overwrites the row matching a key field.

Since `iceberg.tables.upsert-mode-enabled` is not set, every event — whether it was originally an INSERT or UPDATE in Postgres — gets appended as a brand new row in Iceberg.

To set upsert mode:
`iceberg.tables.upsert-mode-enabled`: "true",
`iceberg.tables.upsert.key.fields`: "id"

### Delete handling
Delete is currently set to drop: discard DELETE events - no signal to Iceberg. \
To propagate deletes to Iceberg, you need to change:
- enable the upsert mode
- change delete handling mode
`transforms.unwrap.delete.handling.mode`: "rewrite" - Emits a regular record with a `__deleted=true` field — this is what Iceberg sink can act on

With upsert mode, an UPDATE in Postgres will cause the Iceberg connector to overwrite the row with matching id rather than appending a new one.
With the current config (delete.handling.mode: drop), the DELETE event will be dropped by the ExtractNewRecordState transform and will not appear in Iceberg at all (i.e. keeping the record). 
To observe the delete propagating to Iceberg you'd need to enable upsert mode and change the delete handling to tombstone or rewrite.
