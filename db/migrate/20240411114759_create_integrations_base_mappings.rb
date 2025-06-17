# frozen_string_literal: true

class CreateIntegrationsBaseMappings < ActiveRecord::Migration[7.0]
  def change
    create_table :integration_mappings, id: :uuid do |t|
      t.references :integration, type: :uuid, foreign_key: true, null: false, index: true
      t.references :mappable, type: :uuid, polymorphic: true, null: false
      t.string :type, null: false
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
  end
end
