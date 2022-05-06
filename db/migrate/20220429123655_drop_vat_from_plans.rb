# frozen_string_literal: true

class DropVatFromPlans < ActiveRecord::Migration[7.0]
  def up
    remove_column :plans, :vat_rate
  end

  def down
    add_column :plans, :vat_rate, :float
  end
end
