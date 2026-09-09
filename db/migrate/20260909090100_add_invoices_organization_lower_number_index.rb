# frozen_string_literal: true

class AddInvoicesOrganizationLowerNumberIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Supports the exact, case-insensitive invoice_number filter of the payments
    # list for large organizations. index_invoices_on_number is case-sensitive and
    # not organization-scoped; the trgm index only serves ILIKE.
    add_index :invoices, "organization_id, lower(number)",
      name: "index_invoices_on_organization_id_lower_number",
      algorithm: :concurrently,
      using: :btree,
      if_not_exists: true
  end
end
