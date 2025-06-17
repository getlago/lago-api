# frozen_string_literal: true

class CreateGroupProperties < ActiveRecord::Migration[7.0]
  def change
    create_table :group_properties, id: :uuid do |t|
      t.references :charge, type: :uuid, index: true, foreign_key: {on_delete: :cascade}, null: false
      t.references :group, type: :uuid, index: true, foreign_key: {on_delete: :cascade}, null: false
      t.jsonb :values, null: false, default: {}
      t.timestamps
    end
  end
end
