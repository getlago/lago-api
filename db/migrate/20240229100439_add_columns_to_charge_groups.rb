# frozen_string_literal: true

class AddColumnsToChargeGroups < ActiveRecord::Migration[7.0]
  def change
    change_table :charge_groups, bulk: true do |t|
      t.add_column :pay_in_advance, :boolean, default: false, null: false
      t.add_column :min_amount_cents, :bigint, default: 0, null: false
      t.add_column :invoiceable, :boolean, default: true, null: false
      t.add_column :invoice_display_name, :string
    end
  end
end
