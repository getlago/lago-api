class CreatePermissions < ActiveRecord::Migration[7.0]
  def change
    create_table :permissions, id: :uuid do |t|
      t.belongs_to :membership, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :value, null: false, default: true

      t.index %i[membership_id name], unique: true
    end
  end
end
