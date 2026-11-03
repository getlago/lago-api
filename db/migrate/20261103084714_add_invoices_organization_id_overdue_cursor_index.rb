# frozen_string_literal: true

# Same as the invoice type cursor index, for lists filtered on `payment_overdue = true`.
# Partial, as overdue invoices are a small share of the table.
class AddInvoicesOrganizationIdOverdueCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:invoices, nil, name: :index_invoices_on_organization_id_overdue_cursor, valid: false)
      remove_index :invoices, name: :index_invoices_on_organization_id_overdue_cursor, algorithm: :concurrently
    end

    # The trailing columns are the list order, so a page is read from the index without a sort.
    safety_assured do
      add_index :invoices,
        [:organization_id, :issuing_date, :created_at, :id],
        order: {issuing_date: :desc, created_at: :desc},
        where: "payment_overdue = true",
        name: :index_invoices_on_organization_id_overdue_cursor,
        algorithm: :concurrently,
        if_not_exists: true
    end
  end

  def down
    remove_index :invoices, name: :index_invoices_on_organization_id_overdue_cursor, algorithm: :concurrently, if_exists: true
  end
end
