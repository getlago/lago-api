# frozen_string_literal: true

class DropProRata < ActiveRecord::Migration[7.0]
  def up
    remove_column :charges, :pro_rata
  end

  def down
    add_column :charges, :pro_rata, :boolean, null: false, default: true
  end
end
