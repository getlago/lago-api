# frozen_string_literal: true

class AddMetadataToWalletTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :wallet_transactions, :metadata, :jsonb, default: {}
  end
end
