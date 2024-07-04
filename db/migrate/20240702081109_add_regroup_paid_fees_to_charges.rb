class AddRegroupPaidFeesToCharges < ActiveRecord::Migration[7.1]
  def change
    add_column :charges, :regroup_paid_fees, :integer, default: nil
  end
end
