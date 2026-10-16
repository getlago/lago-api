# frozen_string_literal: true

class CreateAgentRegistrations < ActiveRecord::Migration[8.0]
  def change
    create_enum :agent_registration_status, %w[active revoked]

    create_table :agent_registrations, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :integration, type: :uuid, null: false, foreign_key: true, index: false
      t.string :key_id, null: false
      t.string :public_key, null: false
      t.enum :status, enum_type: :agent_registration_status, null: false, default: "active"
      t.datetime :last_authenticated_at
      t.datetime :revoked_at
      t.timestamps

      t.index %i[integration_id key_id], unique: true
    end
  end
end
