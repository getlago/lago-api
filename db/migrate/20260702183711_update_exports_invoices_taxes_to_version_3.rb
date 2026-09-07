# frozen_string_literal: true

class UpdateExportsInvoicesTaxesToVersion3 < ActiveRecord::Migration[8.0]
  def change
    update_view :exports_invoices_taxes, version: 3, revert_to_version: 2
  end
end
