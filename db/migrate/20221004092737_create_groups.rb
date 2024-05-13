# frozen_string_literal: true

class CreateGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :groups, id: :uuid do |t|
      t.references :billable_metric, type: :uuid, index: true, foreign_key: {on_delete: :cascade}, null: false
      t.references :parent_group, type: :uuid, index: true, foreign_key: {to_table: 'groups'}
      t.string :key, null: false
      t.string :value, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
  end
end
