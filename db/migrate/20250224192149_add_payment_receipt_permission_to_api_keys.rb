# frozen_string_literal: true

class AddPaymentReceiptPermissionToApiKeys < ActiveRecord::Migration[7.1]
  def up
    ApiKey.update_all(permissions: ApiKey.default_permissions) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    ApiKey.update_all( # rubocop:disable Rails/SkipsModelValidations
      permissions: ApiKey.default_permissions.without("payment_receipt")
    )
  end
end
