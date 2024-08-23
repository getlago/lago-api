# frozen_string_literal: true

class AddNullableToInvoiceGracePeriod < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_column_null :customers, :invoice_grace_period, true
      change_column_default :customers, :invoice_grace_period, from: 0, to: nil

      reversible do |dir|
        dir.up do
          # Update all existing customers to a nil invoice_grace_period.
          execute <<-SQL
          UPDATE customers SET invoice_grace_period = NULL;
          SQL
        end
      end
    end
  end
end
