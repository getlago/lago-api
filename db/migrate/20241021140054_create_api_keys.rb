# frozen_string_literal: true

class CreateApiKeys < ActiveRecord::Migration[7.1]
  def up
    create_table :api_keys, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true

      t.string :value, null: false

      t.timestamps
    end

    safety_assured do
      execute <<-SQL
      INSERT INTO api_keys (value, organization_id, created_at, updated_at)
      SELECT organizations.api_key, organizations.id, organizations.created_at, organizations.created_at
      FROM organizations
      SQL
    end
  end

  def down
    safety_assured do
      execute <<-SQL
      UPDATE organizations
      SET api_key = first_api_key.value
      FROM (
          SELECT DISTINCT ON (organization_id) 
              organization_id,
              value
          FROM api_keys
          ORDER BY organization_id, id ASC
      ) first_api_key
      WHERE organizations.id = first_api_key.organization_id
      AND organizations.api_key IS NULL
      SQL
    end

    drop_table :api_keys
  end
end
