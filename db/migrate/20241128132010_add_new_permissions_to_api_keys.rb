# frozen_string_literal: true

class AddNewPermissionsToApiKeys < ActiveRecord::Migration[7.1]
  def up
    ApiKey.update_all(permissions: ApiKey.default_permissions)
  end

  def down
    ApiKey.update_all(
      permissions: ApiKey.default_permissions.without("event", "webhook_jwt_public_key")
    )
  end
end
