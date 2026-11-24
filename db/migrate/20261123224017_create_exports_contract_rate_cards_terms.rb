# frozen_string_literal: true

class CreateExportsContractRateCardsTerms < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_contract_rate_cards_terms
  end
end
