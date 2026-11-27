# frozen_string_literal: true

class AddEventsCopySourceToBillingEngineMigrations < ActiveRecord::Migration[8.1]
  def change
    create_enum :billing_engine_migration_events_copy_source, %w[api raw_topic]

    add_column :billing_engine_migrations,
      :events_copy_source,
      :enum,
      enum_type: "billing_engine_migration_events_copy_source",
      null: false,
      default: "api",
      if_not_exists: true
  end
end
