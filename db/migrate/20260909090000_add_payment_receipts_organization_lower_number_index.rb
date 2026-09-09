# frozen_string_literal: true

class AddPaymentReceiptsOrganizationLowerNumberIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Supports the exact, case-insensitive receipt_number filter of the payments
    # list for large organizations. Same shape as
    # index_invoices_on_organization_id_lower_purchase_order_number.
    add_index :payment_receipts, "organization_id, lower(number)",
      name: "index_payment_receipts_on_organization_id_lower_number",
      algorithm: :concurrently,
      using: :btree,
      if_not_exists: true
  end
end
