# frozen_string_literal: true

class AddInvoiceTypeToInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_enum :subscription_invoicing_reason,
      %w[
        subscription_starting
        subscription_periodic
        subscription_terminating
        in_advance_charge
      ]

    safety_assured do
      change_table :invoice_subscriptions do |t|
        t.enum :invoicing_reason, enum_type: 'subscription_invoicing_reason', null: true

        t.index %w[subscription_id invoicing_reason],
          unique: true,
          where: "invoicing_reason = 'subscription_starting'",
          name: 'index_unique_starting_subscription_invoice'
        t.index %w[subscription_id invoicing_reason],
          unique: true,
          where: "invoicing_reason = 'subscription_terminating'",
          name: 'index_unique_terminating_subscription_invoice'
      end
    end
  end
end
