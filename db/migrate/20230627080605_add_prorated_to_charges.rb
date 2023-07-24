# frozen_string_literal: true

class AddProratedToCharges < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :prorated, :boolean, null: false, default: false
  end
end
