# frozen_string_literal: true

class SetupPgCron < ActiveRecord::Migration[8.0]
  include Migrations::ExtensionHelper

  def up
    safety_assured do      # Check if pg_partman is available on the server
      # No partitioning was configured in previous migrations, we can skip this migration
      return unless pg_extension_exists?("pg_partman")

      if pg_extension_exists?("pg_cron")
        execute <<~SQL
          CREATE EXTENSION IF NOT EXISTS pg_cron;
        SQL
      else
        Rails.logger.debug "pg_cron extension is not available on this PostgreSQL server, skipping..."
      end
    end
  end
end
