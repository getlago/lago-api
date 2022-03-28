class CreateCustomers < ActiveRecord::Migration[7.0]
  def change
    create_table :customers, id: :uuid do |t|
      t.string :external_id, null: false, index: true
      t.string :name
      
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true

      t.timestamps
    end
  end
end
