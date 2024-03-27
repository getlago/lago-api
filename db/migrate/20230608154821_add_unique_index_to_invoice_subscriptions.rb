# frozen_string_literal: true

class AddUniqueIndexToInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_index :invoice_subscriptions,
      %i[subscription_id from_datetime to_datetime],
      unique: true,
      where: "created_at >= '2023-06-09' and recurring is true",
      name: "index_invoice_subscriptions_on_from_and_to_datetime"

    add_index :invoice_subscriptions,
      %i[subscription_id charges_from_datetime charges_to_datetime],
      unique: true,
      where: "created_at >= '2023-06-09' and recurring is true",
      name: "index_invoice_subscriptions_on_charges_from_and_to_datetime"
  end
end
