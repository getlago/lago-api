# frozen_string_literal: true

class AddProductFilterToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :fees, :product_filter, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :fees, :product_filters, column: :product_filter_id, validate: false
  end
end
