# frozen_string_literal: true

class AddInvoiceConsolidationEnabledToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :invoice_consolidation_enabled, :boolean, default: true, null: false
  end
end
