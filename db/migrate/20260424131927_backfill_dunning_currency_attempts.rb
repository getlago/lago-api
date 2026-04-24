# frozen_string_literal: true

class BackfillDunningCurrencyAttempts < ActiveRecord::Migration[8.0]
  def up
    # Seed JSONB from existing single-currency counter to prevent
    # re-dunning customers who already reached max_attempts
    ::Customer
      .where("last_dunning_campaign_attempt > 0 AND currency IS NOT NULL")
      .find_in_batches(batch_size: 1000) do |batch|
      safety_assured do
        ::Customer.where(id: batch.map(&:id))
          .update_all("dunning_currency_attempts = jsonb_build_object(currency, last_dunning_campaign_attempt)") # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end

  def down
  end
end
