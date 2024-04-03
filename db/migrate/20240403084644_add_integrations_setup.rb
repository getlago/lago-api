# frozen_string_literal: true

class AddIntegrationsSetup < ActiveRecord::Migration[7.0]
  def change
    create_table :integrations, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :type, null: false
      t.string :secrets
      t.jsonb :settings, null: false, default: {}

      t.timestamps

      t.index [:code, :organization_id], name: :index_integrations_on_code_and_organization_id, unique: true
    end

    add_column :organizations, :premium_integrations, :string, array: true, null: false, default: []
  end
end
