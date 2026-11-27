# frozen_string_literal: true

class UpdateExportsInvoicesToVersion6 < ActiveRecord::Migration[8.1]
  def change
    update_view :exports_invoices, version: 6, revert_to_version: 5
  end
end
