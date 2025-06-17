# frozen_string_literal: true

class AddFinalizeZeroAmountInvoiceToOrganizations < ActiveRecord::Migration[7.1]
  def change
    add_column :organizations, :finalize_zero_amount_invoice, :boolean, default: true, null: false
  end
end
