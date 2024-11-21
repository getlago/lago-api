# frozen_string_literal: true

class AddPermissionsToApiKeys < ActiveRecord::Migration[7.1]
  def up
    add_column :api_keys, :permissions, :jsonb, null: false, default: {}

    ApiKey.update_all(permissions: ApiKey.default_permissions) # rubocop:disable Rails/SkipsModelValidations

    change_column_default :api_keys, :permissions, nil
  end

  def down
    remove_column :api_keys, :permissions
  end
end
