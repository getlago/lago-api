# frozen_string_literal: true

class AddDeletedAtToUsageThresholds < ActiveRecord::Migration[7.1]
  def change
    add_column :usage_thresholds, :deleted_at, :datetime

    remove_index :usage_thresholds, %i[amount_cents plan_id recurring], unique: true
    remove_index :usage_thresholds, %i[plan_id recurring], unique: true, where: "recurring is true"

    add_index :usage_thresholds, %i[amount_cents plan_id recurring], unique: true, where: 'deleted_at IS NULL'
    add_index :usage_thresholds, %i[plan_id recurring], unique: true, where: "recurring is true and deleted_at IS NULL"
  end
end
