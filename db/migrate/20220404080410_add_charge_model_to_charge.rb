# frozen_string_literal: true

class AddChargeModelToCharge < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :charge_model, :integer, null: false, default: 0
  end
end
