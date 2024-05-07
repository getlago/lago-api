# frozen_string_literal: true

class RemoveIndexFromInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    remove_index :invoice_subscriptions,
      %i[subscription_id from_datetime to_datetime],
      name: 'index_invoice_subscriptions_on_from_and_to_datetime'
  end
end
