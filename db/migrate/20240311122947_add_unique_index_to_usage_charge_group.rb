class AddUniqueIndexToUsageChargeGroup < ActiveRecord::Migration[7.0]
  def change
    add_index :usage_charge_groups,
              [:charge_group_id, :subscription_id],
              unique: true,
              name: 'index_ucg_on_charge_group_id_and_subscription_id'
  end
end
