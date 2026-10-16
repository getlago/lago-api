# frozen_string_literal: true

class DropRetiredPricingTypeAndPlanId < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      remove_column :plans, :pricing_type
      remove_column :plan_rate_cards, :plan_id
      remove_column :contracts, :plan_id
    end

    drop_enum :plan_pricing_type
  end
end
