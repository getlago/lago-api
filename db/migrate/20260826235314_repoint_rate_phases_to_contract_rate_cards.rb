# frozen_string_literal: true

class RepointRatePhasesToContractRateCards < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :rate_phases, :subscription_rate_cards, column: :subscription_rate_card_id

    # The column has never held a value: the subscription runtime is unmerged,
    # so no rate phase references a subscription card anywhere. Renaming in
    # place keeps the exactly-one-parent check constraint, which PostgreSQL
    # rewrites with the column.
    safety_assured do
      rename_column :rate_phases, :subscription_rate_card_id, :contract_rate_card_id
    end

    # rename_column already renamed index_rate_phases_on_subscription_rate_card_id
    # (Rails renames indexes embedding the full column name); only the
    # abbreviated names need an explicit rename.
    rename_index :rate_phases, "index_rate_phases_on_sub_rate_card_id_and_code", "index_rate_phases_on_contract_rate_card_id_and_code"
    rename_index :rate_phases, "index_rate_phases_on_sub_rate_card_id_and_position", "index_rate_phases_on_contract_rate_card_id_and_position"

    # Development databases can hold phases authored on subscription cards by
    # the unmerged runtime branch; the table they referenced is dropped in the
    # next migration, so these rows are debris. Production has none.
    safety_assured do
      execute("DELETE FROM rate_phases WHERE contract_rate_card_id IS NOT NULL")
    end

    # Immediate validation is safe: contract_rate_cards is brand new and the
    # renamed column no longer holds a value.
    safety_assured do
      add_foreign_key :rate_phases, :contract_rate_cards, column: :contract_rate_card_id
    end
  end

  def down
    remove_foreign_key :rate_phases, :contract_rate_cards, column: :contract_rate_card_id

    rename_index :rate_phases, "index_rate_phases_on_contract_rate_card_id_and_position", "index_rate_phases_on_sub_rate_card_id_and_position"
    rename_index :rate_phases, "index_rate_phases_on_contract_rate_card_id_and_code", "index_rate_phases_on_sub_rate_card_id_and_code"

    safety_assured do
      rename_column :rate_phases, :contract_rate_card_id, :subscription_rate_card_id
    end

    safety_assured do
      add_foreign_key :rate_phases, :subscription_rate_cards, column: :subscription_rate_card_id
    end
  end
end
