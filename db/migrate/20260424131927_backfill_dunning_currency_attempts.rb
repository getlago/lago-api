# frozen_string_literal: true

class BackfillDunningCurrencyAttempts < ActiveRecord::Migration[8.0]
  def up
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
  end
end
