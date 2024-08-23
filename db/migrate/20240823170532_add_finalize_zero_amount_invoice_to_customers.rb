# frozen_string_literal: true

class AddFinalizeZeroAmountInvoiceToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :finalize_zero_amount_invoice, :integer
  end
end
