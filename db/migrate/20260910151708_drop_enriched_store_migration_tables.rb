# frozen_string_literal: true

class DropEnrichedStoreMigrationTables < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      drop_table :enriched_store_subscription_migrations
      drop_table :enriched_store_migrations

      drop_enum :enriched_store_sub_migration_status
      drop_enum :enriched_store_migration_status
    end
  end
end
