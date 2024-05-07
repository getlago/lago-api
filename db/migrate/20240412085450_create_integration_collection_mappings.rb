# frozen_string_literal: true

class CreateIntegrationCollectionMappings < ActiveRecord::Migration[7.0]
  def change
    create_table :integration_collection_mappings, id: :uuid do |t|
      t.references :integration, type: :uuid, foreign_key: true, null: false, index: true
      t.integer :mapping_type, null: false
      t.string :type, null: false
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :integration_collection_mappings,
      %i[mapping_type integration_id],
      name: 'index_int_collection_mappings_on_mapping_type_and_int_id',
      unique: true
  end
end
