# frozen_string_literal: true

class ValidateFeesRateCardRateForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :fees, column: :rate_card_rate_id
  end
end
