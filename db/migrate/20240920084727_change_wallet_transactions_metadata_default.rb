# frozen_string_literal: true
class ChangeWalletTransactionsMetadataDefault < ActiveRecord::Migration[7.1]
  def up
    change_column_default :wallet_transactions, :metadata, []
    safety_assured do
      execute <<-SQL
        UPDATE wallet_transactions
        SET metadata = '[]'::jsonb
        WHERE metadata = '{}'::jsonb;
      SQL
    end
  end

  def down
    change_column_default :wallet_transactions, :metadata, {}
    safety_assured do
      execute <<-SQL
        UPDATE wallet_transactions
        SET metadata = '{}'::jsonb
        WHERE metadata = '[]'::jsonb;
      SQL
    end
  end
end
