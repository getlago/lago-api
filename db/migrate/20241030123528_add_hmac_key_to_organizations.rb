# frozen_string_literal: true

class AddHmacKeyToOrganizations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :organizations, :hmac_key, :string, null: false, default: ""

    safety_assured do
      execute <<-SQL
      UPDATE organizations
      SET hmac_key = organizations.api_key
      SQL
    end

    add_index :organizations, :hmac_key, unique: true, algorithm: :concurrently
    change_column_default :organizations, :hmac_key, nil
  end

  def down
    remove_column :organizations, :hmac_key
  end
end
