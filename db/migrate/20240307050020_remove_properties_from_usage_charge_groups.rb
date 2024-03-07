class RemovePropertiesFromUsageChargeGroups < ActiveRecord::Migration[7.0]
  def change
    remove_column :usage_charge_groups, :properties, :jsonb
  end
end
