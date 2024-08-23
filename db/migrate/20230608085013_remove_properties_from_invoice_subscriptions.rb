# frozen_string_literal: true

class RemovePropertiesFromInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      remove_column :invoice_subscriptions, :properties, :jsonb
    end
  end
end
