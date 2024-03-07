# frozen_string_literal: true

class AddPropertiesToChargeGroups < ActiveRecord::Migration[7.0]
  def change
    add_column :charge_groups, :properties, :jsonb, null: false, default: {}
  end
end
