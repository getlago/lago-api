# frozen_string_literal: true

class CreateUsageChargeGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :usage_charge_groups, id: :uuid do |t|
      t.bigint :current_package_count, null: false, default: 1
      t.jsonb :available_group_usage
      t.jsonb :properties, null: false, default: {}

      t.timestamps
      t.datetime :deleted_at

      t.references :charge_group, foreign_key: true, type: :uuid, null: false
      t.references :subscription, foreign_key: true, type: :uuid, null: false
    end
  end
end
