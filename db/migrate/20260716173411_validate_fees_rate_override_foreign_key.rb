# frozen_string_literal: true

class ValidateFeesRateOverrideForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :fees, column: :rate_override_id
  end
end
