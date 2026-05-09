#!/bin/bash
# Executed by the postgres entrypoint on first master initialisation.
# Creates the replication role and adds a pg_hba entry for it.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE ROLE $POSTGRES_REPLICATION_USER WITH REPLICATION LOGIN PASSWORD '$POSTGRES_REPLICATION_PASSWORD';
EOSQL

echo "host replication $POSTGRES_REPLICATION_USER 0.0.0.0/0 md5" >> "$PGDATA/pg_hba.conf"
