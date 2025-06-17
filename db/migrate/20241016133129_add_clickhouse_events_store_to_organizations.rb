# frozen_string_literal: true

class AddClickhouseEventsStoreToOrganizations < ActiveRecord::Migration[7.1]
  def change
    add_column :organizations, :clickhouse_events_store, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
            UPDATE organizations
            SET clickhouse_events_store = true
            WHERE clickhouse_aggregation = true
          SQL
        end
      end
    end
  end
end
