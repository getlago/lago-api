# frozen_string_literal: true

class AddRateCardRateToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :fees, :rate_card_rate, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :fees, :rate_card_rates, column: :rate_card_rate_id, validate: false
  end
end
