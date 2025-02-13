# frozen_string_literal: true

class AddAmountDetailsToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :amount_details, :jsonb, null: false, default: "{}"
  end
end
