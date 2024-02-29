class AddColumnsToChargeGroups < ActiveRecord::Migration[7.0]
  def change
    add_column :charge_groups, :pay_in_advance, :boolean, default: false, null: false
    add_column :charge_groups, :min_amount_cents, :bigint, default: 0, null: false
    add_column :charge_groups, :invoiceable, :boolean, default: true, null: false
    add_column :charge_groups, :invoice_display_name, :string
  end
end
