# frozen_string_literal: true

class ValidateFeesProductFilterForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :fees, column: :product_filter_id
  end
end
