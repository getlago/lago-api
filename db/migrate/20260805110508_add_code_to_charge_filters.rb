# frozen_string_literal: true

class AddCodeToChargeFilters < ActiveRecord::Migration[8.0]
  def change
    add_column :charge_filters, :code, :string
  end
end
