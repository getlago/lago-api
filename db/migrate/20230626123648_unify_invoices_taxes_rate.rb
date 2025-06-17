# frozen_string_literal: true

class UnifyInvoicesTaxesRate < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          /* Unify invoices->taxes_rate to be a number */
          UPDATE invoices
          SET taxes_rate = 0.0
          WHERE taxes_rate = 'NaN'::NUMERIC;
          SQL
        end
      end
    end
  end
end
