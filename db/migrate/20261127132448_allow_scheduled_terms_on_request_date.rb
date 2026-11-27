# frozen_string_literal: true

class AllowScheduledTermsOnRequestDate < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_retryable_index(:index_current_contract_rate_card_terms, unique: true,
      where: "application_timing = 'current_billing_cycle'")
    add_retryable_index(:index_contract_rate_card_terms_by_date)
    remove_index :contract_rate_cards_terms, name: :index_contract_rate_cards_terms_on_card_and_effective_date,
      algorithm: :concurrently, if_exists: true
  end

  def down
    # Keep every row if a request date is shared. The old unique index cannot be
    # restored until those scheduled terms have been migrated by the operator.
    add_retryable_index(:index_contract_rate_cards_terms_on_card_and_effective_date, unique: true)
    remove_index :contract_rate_cards_terms, name: :index_current_contract_rate_card_terms, algorithm: :concurrently, if_exists: true
    remove_index :contract_rate_cards_terms, name: :index_contract_rate_card_terms_by_date, algorithm: :concurrently, if_exists: true
  end

  private

  def add_retryable_index(name, **options)
    if index_exists?(:contract_rate_cards_terms, name:, valid: false)
      remove_index :contract_rate_cards_terms, name:, algorithm: :concurrently
    end
    add_index :contract_rate_cards_terms, [:contract_rate_card_id, :effective_date],
      name:, algorithm: :concurrently, if_not_exists: true, **options
  end
end
