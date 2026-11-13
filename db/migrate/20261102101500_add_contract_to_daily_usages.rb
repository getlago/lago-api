# frozen_string_literal: true

class AddContractToDailyUsages < ActiveRecord::Migration[8.0]
  def change
    add_column :daily_usages, :contract_id, :uuid, if_not_exists: true
    add_column :daily_usages, :contract_rate_card_id, :uuid, if_not_exists: true
    add_column :daily_usages, :external_contract_id, :string, if_not_exists: true

    # A contract's daily usage has no subscription.
    change_column_null :daily_usages, :subscription_id, true
    change_column_null :daily_usages, :external_subscription_id, true

    add_foreign_key :daily_usages, :contracts, column: :contract_id, validate: false, if_not_exists: true
    add_foreign_key :daily_usages, :contract_rate_cards, column: :contract_rate_card_id, validate: false, if_not_exists: true
    add_foreign_key :daily_usages,
      :contract_rate_cards,
      column: [:contract_rate_card_id, :contract_id],
      primary_key: [:id, :contract_id],
      name: :fk_daily_usages_contract_rate_card_contract,
      validate: false,
      if_not_exists: true

    add_check_constraint :daily_usages,
      "(subscription_id IS NOT NULL AND external_subscription_id IS NOT NULL AND " \
      "contract_id IS NULL AND contract_rate_card_id IS NULL AND external_contract_id IS NULL) OR " \
      "(subscription_id IS NULL AND external_subscription_id IS NULL AND " \
      "contract_id IS NOT NULL AND contract_rate_card_id IS NOT NULL AND external_contract_id IS NOT NULL)",
      name: :daily_usages_subscription_or_contract,
      validate: false,
      if_not_exists: true
  end
end
