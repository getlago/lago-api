# frozen_string_literal: true

class AddColumnsToChargeGroups < ActiveRecord::Migration[7.0]
  def change
    change_table :charge_groups, bulk: true do |t|
      t.boolean :pay_in_advance, default: false, null: false
      t.bigint :min_amount_cents, default: 0, null: false
      t.boolean :invoiceable, default: true, null: false
      t.string :invoice_display_name
    end
  end
end
