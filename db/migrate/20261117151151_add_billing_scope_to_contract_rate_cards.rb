# frozen_string_literal: true

class AddBillingScopeToContractRateCards < ActiveRecord::Migration[8.1]
  def change
    create_enum :contract_rate_card_billing_scope, %w[cycle segment]

    add_column :contract_rate_cards, :billing_scope, :enum,
      enum_type: :contract_rate_card_billing_scope,
      default: "cycle",
      null: false,
      if_not_exists: true
  end
end
