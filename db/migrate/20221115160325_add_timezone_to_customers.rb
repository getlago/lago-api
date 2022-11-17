# frozen_string_literal: true

class AddTimezoneToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :timezone, :string, null: true
  end
end
