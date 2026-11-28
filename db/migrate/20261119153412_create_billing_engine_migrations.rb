# frozen_string_literal: true

class CreateBillingEngineMigrations < ActiveRecord::Migration[8.1]
  def change
    create_enum :billing_engine_migration_status, %w[shadowing paused aborted]

    create_table :billing_engine_migrations, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: {unique: true}
      t.references :shadow_organization, type: :uuid, foreign_key: {to_table: :organizations}, null: false, index: {unique: true}
      t.enum :status, enum_type: "billing_engine_migration_status", null: false, default: "shadowing"
      t.jsonb :plan_mapping, null: false, default: {}

      t.timestamps
    end
  end
end
