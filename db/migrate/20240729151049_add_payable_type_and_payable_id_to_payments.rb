# frozen_string_literal: true

class AddPayableTypeAndPayableIdToPayments < ActiveRecord::Migration[7.1]
  def change
    change_table :payments, bulk: true do |t|
      t.string :payable_type, null: false, default: "Invoice"
      t.uuid :payable_id
    end

    # invoice_id is now deprecated and will be removed in the future
    change_column_null :payments, :invoice_id, true

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE payments
          SET payable_id = invoice_id
        SQL
      end
    end
  end
end
