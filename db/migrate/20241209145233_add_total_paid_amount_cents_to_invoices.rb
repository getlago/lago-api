# frozen_string_literal: true

class AddTotalPaidAmountCentsToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :total_paid_amount_cents, :bigint, null: false, default: 0
  end
end
