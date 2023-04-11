class AddMinAmountCentsToCharges < ActiveRecord::Migration[7.0]
  def change
    add_column :charges, :min_amount_cents, :bigint, null: false, default: 0
  end
end
