class CreateSubscriptionCharges < ActiveRecord::Migration[7.0]
  def change
    create_table :subscription_charges, id: :primary_key do |t|
      t.string :plan_title
      t.integer :subscription_instance_id
      t.boolean :is_finalized

      t.timestamps
    end
  end
end
