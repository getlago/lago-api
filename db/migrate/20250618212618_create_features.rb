# frozen_string_literal: true

class CreateFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :features, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.datetime :deleted_at
      t.timestamps

      t.index [:organization_id, :code], unique: true, where: "deleted_at IS NULL"
    end

    create_table :privileges, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :feature, type: :uuid, null: false, foreign_key: true, index: true
      t.string :code, null: false
      t.string :name
      t.string :value_type, null: false, default: "string"
      t.datetime :deleted_at
      t.timestamps

      t.index [:feature_id, :code], unique: true, where: "deleted_at IS NULL"
    end
  end
end
