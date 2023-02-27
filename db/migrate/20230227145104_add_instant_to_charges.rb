# frozen_string_literal: true

class AddInstantToCharges < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :instant, :boolean, null: false, default: false
  end
end
