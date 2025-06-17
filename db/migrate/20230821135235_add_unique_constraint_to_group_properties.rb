# frozen_string_literal: true

class AddUniqueConstraintToGroupProperties < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_index :group_properties, %i[charge_id group_id], unique: true
    end
  end
end
