class CreatePartners < ActiveRecord::Migration[7.1]
  def change
    create_table :partners, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.string :name

      t.timestamps
    end
  end
end
