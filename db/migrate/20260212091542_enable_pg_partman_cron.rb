# frozen_string_literal: true

require Rails.root.join("lib/migrations/extension_helper")

class EnablePgPartmanCron < ActiveRecord::Migration[8.0]
  include Migrations::ExtensionHelper

  def up
    safety_assured do
      # No partitioning was configured in previous migrations, we can skip this migration
      return unless pg_extension_exists?("pg_partman")

      if pg_extension_exists?("pg_cron")
        execute <<~SQL
          SELECT cron.schedule('@hourly', $$CALL partman.run_maintenance_proc()$$);
        SQL
      else
        Rails.logger.debug "pg_cron extension is not available on this PostgreSQL server, skipping..."
      end
    end
  end
end
