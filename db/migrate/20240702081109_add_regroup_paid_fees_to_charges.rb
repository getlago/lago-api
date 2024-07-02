class AddRegroupPaidFeesToCharges < ActiveRecord::Migration[7.1]
  def change
    add_column :charges, :regroup_paid_fees, :string, default: nil
  end
end
