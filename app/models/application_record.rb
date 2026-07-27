# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Two roles on the same physical database:
  #   :writing (default) — DATABASE_PROXY_URL when set, else DATABASE_URL.
  #                        Normal traffic, goes through the RDS Proxy where
  #                        one is deployed.
  #   :direct            — always DATABASE_URL. Bypasses the pooler for
  #                        statements that would otherwise session-pin
  #                        (>16 KB on RDS Proxy for Postgres).
  # Use with `ApplicationRecord.connected_to(role: :direct) { ... }`.
  # When DATABASE_PROXY_URL is unset both roles resolve to DATABASE_URL,
  # so `:direct` becomes a no-op.
  connects_to database: {writing: :primary, direct: :direct}

  # In test env, Rails opens a distinct connection pool for `:direct`
  # even though the config points at the same DB — separate pools mean
  # separate PG sessions and separate transactions, and DatabaseCleaner
  # only wraps the default (:writing) pool. Fixtures written via the
  # default pool wouldn't be visible when the app switches to `:direct`,
  # which would break every scenario spec that exercises the biller.
  # Short-circuit the role swap so `:direct` queries land on the
  # currently-active pool.
  if Rails.env.test?
    def self.connected_to(role: nil, **kwargs)
      return yield if role == :direct
      super
    end
  end

  # Avoid raising ActiveRecord::PreparedStatementCacheExpired
  # from transactions when a migration is adding a new column
  self.ignored_columns = [:__fake_column__]
end
