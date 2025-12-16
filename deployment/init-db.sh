#!/bin/bash
set -ex

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER"  <<-EOSQL
	CREATE USER cara WITH PASSWORD '${DB_PASSWORD}';
	GRANT ALL PRIVILEGES ON DATABASE cara_prod TO cara;
	ALTER DATABASE cara_prod OWNER TO cara;
EOSQL
