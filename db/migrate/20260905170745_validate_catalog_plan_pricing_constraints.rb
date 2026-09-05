# frozen_string_literal: true

class ValidateCatalogPlanPricingConstraints < ActiveRecord::Migration[8.0]
  def up
    validate_foreign_key :plan_rate_cards, :catalog_plans
    validate_check_constraint :plan_rate_cards, name: "plan_rate_cards_check_exactly_one_plan"

    validate_foreign_key :contracts, :catalog_plans
    validate_check_constraint :contracts, name: "contracts_check_single_plan"
  end

  def down
  end
end
