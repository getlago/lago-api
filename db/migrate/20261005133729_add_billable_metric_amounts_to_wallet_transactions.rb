# frozen_string_literal: true

class AddBillableMetricAmountsToWalletTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :wallet_transactions, :billable_metric_amounts, :jsonb, if_not_exists: true
  end
end
