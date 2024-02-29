class CreateChargeGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :charge_groups, id: :uuid do |t|
      t.timestamps
      t.datetime :deleted_at
    end

    add_reference :charges, :charge_group, foreign_key: true, type: :uuid
  end
end
