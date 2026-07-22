# frozen_string_literal: true

class AddWalletRefreshRequestedAtToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :wallet_refresh_requested_at, :datetime
  end
end
