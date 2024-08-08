# frozen_string_literal: true

class CreateLifetimeUsage < ActiveRecord::Migration[7.1]
  def change
    create_table :lifetime_usages, id: :uuid do |t|
      t.references :organization, null: false, index: true, foreign_key: true, type: :uuid
      t.belongs_to :subscription, null: false, index: {unique: true}, foreign_key: true, type: :uuid
      t.bigint :current_usage_amount_cents, null: false, default: 0
      t.bigint :invoiced_usage_amount_cents, null: false, default: 0
      t.boolean :recalculate_current_usage, null: false, default: false
      t.boolean :recalculate_invoiced_usage, null: false, default: false
      t.timestamp :current_usage_amount_refreshed_at
      t.timestamp :invoiced_usage_amount_refreshed_at

      t.timestamps
      t.datetime :deleted_at
    end

    add_index :lifetime_usages, %i[recalculate_current_usage], where: "deleted_at IS NULL and recalculate_current_usage = 't'"
    add_index :lifetime_usages, %i[recalculate_invoiced_usage], where: "deleted_at IS NULL and recalculate_invoiced_usage = 't'"
  end
end
