#!/bin/bash
#
# `set -e` matters more here than it looks. This script migrates and seeds
# before it execs Puma, and without it a failure in any of those steps just
# scrolls past and a server boots anyway on a half-prepared database. That is
# how v1.54.0's seed failure stayed invisible. migrate.sh has always had it.
#
# Safe for normal boots: roles:seed_predefined is find_or_create_by!, and
# signup:seed_organization is a no-op unless LAGO_CREATE_ORG is true. The only
# k8s consumer of this script is the single-replica dev-us-1 preview base — the
# multi-replica deployments run start.api.sh, which does not migrate — so this
# cannot turn a concurrent-migration race into a crash loop.
set -e

if [ "$RAILS_ENV" == "staging" ]
then
  bundle exec rake db:prepare
fi

rm -f ./tmp/pids/server.pid

if [ -v LAGO_CLICKHOUSE_MIGRATIONS_ENABLED ] && [ "$LAGO_CLICKHOUSE_MIGRATIONS_ENABLED" == "true" ]
then
  bundle exec rails db:migrate:primary
  bundle exec rails db:migrate:clickhouse
else
  bundle exec rails db:migrate
fi

# Must run before signup:seed_organization, which looks the admin role up by
# `admin: true` alone and would otherwise create a Role with a NULL code/name
# and fail the NOT NULL constraint. migrate.sh pairs these two the same way.
bundle exec rails roles:seed_predefined

bundle exec rails signup:seed_organization
exec bundle exec rails s -b ::
