# frozen_string_literal: true

class CreateExportsContractRateCards < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_contract_rate_cards
  end
end
