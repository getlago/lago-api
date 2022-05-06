# frozen_string_literal: true

class DropVatFromCharges < ActiveRecord::Migration[7.0]
  def up
    remove_column :charges, :vat_rate
  end

  def down
    add_column :charges, :vat_rate, :float
  end
end
