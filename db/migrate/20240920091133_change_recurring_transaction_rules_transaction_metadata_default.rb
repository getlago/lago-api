# frozen_string_literal: true

class ChangeRecurringTransactionRulesTransactionMetadataDefault < ActiveRecord::Migration[7.1]
  def up
    change_column_default :recurring_transaction_rules, :transaction_metadata, []
    safety_assured do
      execute <<-SQL
        UPDATE recurring_transaction_rules
        SET transaction_metadata = '[]'::jsonb
        WHERE transaction_metadata = '{}'::jsonb;
      SQL
    end
  end

  def down
    change_column_default :recurring_transaction_rules, :transaction_metadata, {}
    safety_assured do
      execute <<-SQL
        UPDATE recurring_transaction_rules
        SET transaction_metadata = '{}'::jsonb
        WHERE transaction_metadata = '[]'::jsonb;
      SQL
    end
  end
end
