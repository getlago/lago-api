# frozen_string_literal: true

class RemoveCreditsAutoRefreshedFromOrganizations < ActiveRecord::Migration[7.0]
  def change
    remove_column :organizations, :credits_auto_refreshed, :boolean

    change_table :wallets, bulk: true do |t|
      t.bigint :ongoing_balance_cents, default: 0, null: false
      t.bigint :ongoing_usage_balance_cents, default: 0, null: false

      t.decimal :credits_ongoing_balance, precision: 30, scale: 5, default: "0.0", null: false
      t.decimal :credits_ongoing_usage_balance, precision: 30, scale: 5, default: "0.0", null: false
    end
  end
end
