# frozen_string_literal: true

class UpdateExportsInvoicesToVersion5 < ActiveRecord::Migration[8.0]
  def change
    update_view :exports_invoices, version: 5, revert_to_version: 4
  end
end
