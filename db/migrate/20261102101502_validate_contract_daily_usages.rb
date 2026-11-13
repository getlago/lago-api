# frozen_string_literal: true

class ValidateContractDailyUsages < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :daily_usages, :contracts, column: :contract_id
    validate_foreign_key :daily_usages, :contract_rate_cards, column: :contract_rate_card_id
    validate_foreign_key :daily_usages,
      :contract_rate_cards,
      column: [:contract_rate_card_id, :contract_id],
      primary_key: [:id, :contract_id],
      name: :fk_daily_usages_contract_rate_card_contract
    validate_check_constraint :daily_usages, name: :daily_usages_subscription_or_contract
  end
end
