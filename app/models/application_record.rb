# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # :writing (default) uses DATABASE_PROXY_URL when set, else DATABASE_URL.
  # :direct always uses DATABASE_URL to bypass the pooler for statements
  # that would session-pin (>16 KB on RDS Proxy for Postgres).
  connects_to database: {writing: :primary, direct: :direct}

  # Avoid raising ActiveRecord::PreparedStatementCacheExpired
  # from transactions when a migration is adding a new column
  self.ignored_columns = [:__fake_column__]
end
