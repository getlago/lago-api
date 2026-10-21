# frozen_string_literal: true

# Payment receipt endpoints used to be authorized by the invoice permission. Copying it keeps
# every key's effective access unchanged when they switch to the payment_receipt permission.
class AlignPaymentReceiptApiKeyPermissionsWithInvoice < ActiveRecord::Migration[8.1]
  def up
    ApiKey.unscoped
      .where("permissions->'payment_receipt' IS DISTINCT FROM COALESCE(permissions->'invoice', '[]'::jsonb)")
      .in_batches(of: 1000)
      .update_all([ # rubocop:disable Rails/SkipsModelValidations
        "permissions = jsonb_set(permissions, '{payment_receipt}', COALESCE(permissions->'invoice', '[]'::jsonb)), updated_at = ?",
        Time.current
      ])
  end

  def down
  end
end
