#!/usr/bin/env bash
# Prints the number of tables of a schema in $DATABASE_URL. The Rails metadata
# tables (`schema_migrations`, `ar_internal_metadata`) are left out, as Rails
# creates them in the first schema of the search path that exists.
set -euo pipefail

psql "$DATABASE_URL" -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema = '$1' AND table_name NOT IN ('schema_migrations', 'ar_internal_metadata')"
