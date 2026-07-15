# frozen_string_literal: true

class AddInvoicesOrganizationPurchaseOrderNumberIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :invoices, [:organization_id, :purchase_order_number],
      name: "index_invoices_on_organization_id_purchase_order_number",
      algorithm: :concurrently,
      using: :btree,
      if_not_exists: true
  end
end
