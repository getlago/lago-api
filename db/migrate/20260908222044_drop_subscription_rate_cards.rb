# frozen_string_literal: true

class DropSubscriptionRateCards < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      drop_table :subscription_rate_cards
    end
  end
end
