# frozen_string_literal: true

class AddApplicationTimingToContractRateCardsUnits < ActiveRecord::Migration[8.1]
  def change
    create_enum :contract_rate_cards_units_application_timing, %w[current_billing_cycle next_billing_cycle]

    add_column :contract_rate_cards_units, :application_timing, :enum,
      enum_type: :contract_rate_cards_units_application_timing,
      default: "current_billing_cycle",
      null: false,
      if_not_exists: true
  end
end
