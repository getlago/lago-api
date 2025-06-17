# frozen_string_literal: true

class AddUniqueIndexOnInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_index :invoice_subscriptions, %i[invoice_id subscription_id], unique: true, where: "created_at >= '2023-11-23'"
    end
  end
end
