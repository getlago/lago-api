# frozen_string_literal: true

class ValidateAdjustedFeesFixedChargesForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :adjusted_fees, :fixed_charges
  end
end
