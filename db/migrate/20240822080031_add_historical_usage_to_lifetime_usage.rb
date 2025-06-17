# frozen_string_literal: true

class AddHistoricalUsageToLifetimeUsage < ActiveRecord::Migration[7.1]
  def change
    add_column :lifetime_usages, :historical_usage_amount_cents, :bigint, default: 0, null: false
  end
end
