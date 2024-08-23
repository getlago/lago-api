# frozen_string_literal: true

class AddPaymentStatusToFees < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :fees, bulk: true do |t|
        # NOTE: will be changed after migration
        t.integer :payment_status, null: true

        t.datetime :succeeded_at
        t.datetime :failed_at
        t.datetime :refunded_at
      end

      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE fees
          SET payment_status = invoices.payment_status
          FROM invoices
          WHERE invoices.id = fees.invoice_id
          SQL
        end

        change_column_null :fees, :payment_status, false
        change_column_default :fees, :payment_status, 0
      end
    end
  end
end
