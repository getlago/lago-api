# frozen_string_literal: true

class AddHmacKeyToOrganizations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :organizations, :hmac_key, :string, null: false, default: ""

    safety_assured do
      execute <<-SQL
      UPDATE organizations
      SET hmac_key = first_api_key.value
      FROM (
          SELECT DISTINCT ON (organization_id)
              organization_id,
              value
          FROM api_keys
          ORDER BY organization_id, id ASC
      ) first_api_key
      WHERE organizations.id = first_api_key.organization_id
      SQL
    end

    add_index :organizations, :hmac_key, unique: true, algorithm: :concurrently
    change_column_default :organizations, :hmac_key, nil
  end

  def down
    remove_column :organizations, :hmac_key
  end
end
