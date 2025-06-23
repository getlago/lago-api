# frozen_string_literal: true

class RemoveAmountCurrencyNullConstraintFromCharges < ActiveRecord::Migration[7.0]
  def up
    change_column :charges, :amount_currency, :string, null: true
  end

  def down
    change_column :charges, :amount_currency, :string, null: false
  end
end
