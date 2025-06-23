# frozen_string_literal: true

class CreateDataExportParts < ActiveRecord::Migration[7.1]
  def change
    create_table :data_export_parts, id: :uuid do |t|
      t.integer :index
      t.references :data_export, type: :uuid, foreign_key: true, null: false, index: true
      t.uuid :object_ids, null: false, array: true
      t.boolean :completed, null: false, default: false
      t.text :csv_lines

      t.timestamps
    end
  end
end
