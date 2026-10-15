# frozen_string_literal: true

class AddOngoingBillableMetricAmountsToWallets < ActiveRecord::Migration[8.0]
  def change
    add_column :wallets, :ongoing_billable_metric_amounts, :jsonb, default: {}, null: false, if_not_exists: true
  end
end
