# frozen_string_literal: true

class AddPropertiesToInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :invoice_subscriptions, :properties, :jsonb, null: false, default: "{}"

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE invoice_subscriptions
          SET properties = COALESCE((
            SELECT fees.properties
            FROM fees
            WHERE fees.subscription_id = invoice_subscriptions.subscription_id
              AND fees.invoice_id = invoice_subscriptions.invoice_id
            ORDER BY fees.created_at ASC
            LIMIT 1
          ), '{}');
        SQL
      end
    end
  end
end
