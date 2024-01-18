# frozen_string_literal: true

class RemoveCreditsAutoRefreshedFromOrganizations < ActiveRecord::Migration[7.0]
  def change
    remove_column :organizations, :credits_auto_refreshed, :boolean

    add_column :wallets, :upcoming_balance_cents, :bigint, default: 0, null: false
    add_column :wallets, :upcoming_credits_balance, :decimal, precision: 30, scale: 5, default: '0.0', null: false
  end
end
