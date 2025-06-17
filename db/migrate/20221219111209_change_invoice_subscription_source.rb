# frozen_string_literal: true

class ChangeInvoiceSubscriptionSource < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :invoice_subscriptions, bulk: true do |t|
        t.remove :source

        t.boolean :recurring, null: true
      end

      execute <<-SQL
      UPDATE invoice_subscriptions
      SET recurring = true;
      SQL

      change_column_null :invoice_subscriptions, :recurring, null: false
    end
  end

  def down
    change_table :invoice_subscriptions, bulk: true do |t|
      t.integer :source
      t.remove :recurring
    end
  end
end
