# frozen_string_literal: true

class DenormalizeCustomerOnSubscriptionRateCards < ActiveRecord::Migration[8.0]
  # The billing clock scans and groups by customer. Carrying the id on the card keeps that
  # scan index-only instead of joining through subscriptions on every tick.
  def change
    safety_assured do
      add_column :subscription_rate_cards, :customer_id, :uuid

      up_only do
        execute(<<~SQL)
          UPDATE subscription_rate_cards s
          SET customer_id = sub.customer_id
          FROM subscriptions sub
          WHERE sub.id = s.subscription_id AND s.customer_id IS NULL
        SQL
      end

      change_column_null :subscription_rate_cards, :customer_id, false
      add_foreign_key :subscription_rate_cards, :customers
      add_index :subscription_rate_cards, :customer_id
    end
  end
end
