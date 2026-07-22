# frozen_string_literal: true

class UpdateExportsInvoiceSubscriptionsToVersion2 < ActiveRecord::Migration[8.0]
  def change
    update_view :exports_invoice_subscriptions, version: 2, revert_to_version: 1
  end
end
