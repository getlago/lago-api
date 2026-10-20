# frozen_string_literal: true

# Serves the taxes of one rate card in the order of the v2 lists, for the
# `/api/v2/rate_cards/:code/taxes` endpoint. Not partial: the table has no `deleted_at`.
class AddRateCardsTaxesCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:rate_cards_taxes, nil, name: :index_rate_cards_taxes_by_cursor, valid: false)
      remove_index :rate_cards_taxes, name: :index_rate_cards_taxes_by_cursor, algorithm: :concurrently
    end

    add_index :rate_cards_taxes,
      [:rate_card_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      name: :index_rate_cards_taxes_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :rate_cards_taxes, name: :index_rate_cards_taxes_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
