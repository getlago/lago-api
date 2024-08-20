# frozen_string_literal: true

class AddNegativeAmountCentsToInvoice < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :negative_amount_cents, :bigint, null: false, default: 0
  end
end
