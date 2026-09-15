# frozen_string_literal: true

class ValidateCatalogPlanPricingForeignKeys < ActiveRecord::Migration[8.0]
  def up
    validate_foreign_key :plan_rate_cards, :catalog_plans
    validate_foreign_key :contracts, :catalog_plans
  end

  def down
  end
end
