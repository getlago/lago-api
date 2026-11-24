# frozen_string_literal: true

class IndexTimestampedContractRateCardTerms < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:contract_rate_cards_terms, nil, name: :index_contract_rate_card_terms_on_card_and_instant, valid: false)
      remove_index :contract_rate_cards_terms, name: :index_contract_rate_card_terms_on_card_and_instant, algorithm: :concurrently
    end

    add_index :contract_rate_cards_terms, [:contract_rate_card_id, :effective_at],
      unique: true, name: :index_contract_rate_card_terms_on_card_and_instant,
      algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :contract_rate_cards_terms, name: :index_contract_rate_card_terms_on_card_and_instant,
      algorithm: :concurrently, if_exists: true
  end
end
