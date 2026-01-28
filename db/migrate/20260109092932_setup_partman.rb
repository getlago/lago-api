# frozen_string_literal: true

class SetupPartman < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      # Check if pg_partman is available on the server
      result = execute <<~SQL
        SELECT 1 FROM pg_available_extensions WHERE name = 'pg_partman';
      SQL

      if result.ntuples.zero?
        Rails.logger.debug "pg_partman extension is not available on this PostgreSQL server, skipping..."
      else
        execute <<~SQL
          CREATE SCHEMA IF NOT EXISTS partman;
          CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;
        SQL
      end
    end
  end
end
