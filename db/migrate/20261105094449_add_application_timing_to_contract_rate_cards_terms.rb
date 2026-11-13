# frozen_string_literal: true

class AddApplicationTimingToContractRateCardsTerms < ActiveRecord::Migration[8.1]
  def change
    create_enum :contract_rate_cards_terms_application_timing, %w[current_billing_cycle next_billing_cycle]

    add_column :contract_rate_cards_terms, :application_timing, :enum,
      enum_type: :contract_rate_cards_terms_application_timing,
      default: "current_billing_cycle",
      null: false,
      if_not_exists: true
  end
end
