# frozen_string_literal: true

class UpdateExportsWalletTransactionsToVersion4 < ActiveRecord::Migration[8.0]
  def change
    update_view :exports_wallet_transactions, version: 4, revert_to_version: 3
  end
end
