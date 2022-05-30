# frozen_string_literal: true

class AddUnitsToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :units, :decimal, null: false, default: 0
  end
end
