# frozen_string_literal: true

class AddPayInAdvanceOnPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :pay_in_advance, :boolean, default: false, null: false
  end
end
