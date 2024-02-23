class CreateChargePackageGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :charge_package_groups, id: :uuid do |t|
      t.bigint :current_package_count, null: false, default: 1
      t.jsonb :available_group_usage

      t.timestamps
    end

    add_reference :charges, :charge_package_group, foreign_key: true, type: :uuid
  end
end
