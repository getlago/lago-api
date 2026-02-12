# frozen_string_literal: true

class SetupPgCron < ActiveRecord::Migration[8.0]
  def up
    safety_assured do      # Check if pg_partman is available on the server
      partman_result = execute <<~SQL
        SELECT 1 FROM pg_available_extensions WHERE name = 'pg_partman';
      SQL
      # No partitioning was configured in previous migrations, we can skip this migration
      return if partman_result.ntuples.zero?

      # Check if pg_cron is available on the server
      result = execute <<~SQL
        SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'
      SQL

      if result.ntuples.zero?
        Rails.logger.debug "pg_cron extension is not available on this PostgreSQL server, skipping..."
      else
        execute <<~SQL
          CREATE EXTENSION IF NOT EXISTS pg_cron;
        SQL
      end
    end
  end
end
