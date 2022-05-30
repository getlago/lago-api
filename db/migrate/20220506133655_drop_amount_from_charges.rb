# frozen_string_literal: true

class DropAmountFromCharges < ActiveRecord::Migration[7.0]
  def change
    remove_column :charges, :amount_cents
  end
end
