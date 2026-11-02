# frozen_string_literal: true

# `index_invoices_by_cursor` leads with `issuing_date`, so a v2 invoice list filtered on an old
# `created_at` range would walk every newer invoice of the organization: this one seeks the range.
class AddInvoicesCreatedAtIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:invoices, nil, name: :index_invoices_on_organization_id_and_created_at, valid: false)
      remove_index :invoices, name: :index_invoices_on_organization_id_and_created_at, algorithm: :concurrently
    end

    add_index :invoices,
      [:organization_id, :created_at],
      name: :index_invoices_on_organization_id_and_created_at,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :invoices, name: :index_invoices_on_organization_id_and_created_at, algorithm: :concurrently, if_exists: true
  end
end
