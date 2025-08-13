# frozen_string_literal: true

class BackfillAndEnforceWalletPriority < ActiveRecord::Migration[8.0]
  def up
    change_column_default :wallets, :priority, 50
    execute "UPDATE wallets SET priority = 50 WHERE priority IS NULL"
    change_column_null :wallets, :priority, false
  end

  def down
    change_column_null :wallets, :priority, true
    change_column_default :wallets, :priority, nil
  end
end
