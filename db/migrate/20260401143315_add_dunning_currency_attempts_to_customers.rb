# frozen_string_literal: true

class AddDunningCurrencyAttemptsToCustomers < ActiveRecord::Migration[8.0]
  def up
    add_column :customers, :dunning_currency_attempts, :jsonb, default: {}, null: false

    # Seed JSONB from existing single-currency counter to prevent
    # re-dunning customers who already reached max_attempts
    safety_assured do
      execute <<~SQL
        UPDATE customers
        SET dunning_currency_attempts = jsonb_build_object(currency, last_dunning_campaign_attempt)
        WHERE last_dunning_campaign_attempt > 0
          AND currency IS NOT NULL
      SQL
    end
  end

  def down
    safety_assured { remove_column :customers, :dunning_currency_attempts }
  end
end
