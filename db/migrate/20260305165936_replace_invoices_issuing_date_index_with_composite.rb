# frozen_string_literal: true

class ReplaceInvoicesIssuingDateIndexWithComposite < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # All issuing_date queries are scoped to organization_id;
    # the DESC order matches the default sort in InvoicesQuery
    add_index :invoices, [:organization_id, :issuing_date],
      order: {issuing_date: :desc},
      algorithm: :concurrently,
      if_not_exists: true

    remove_index :invoices, name: :index_invoices_on_issuing_date, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :invoices, :issuing_date, algorithm: :concurrently, if_not_exists: true

    remove_index :invoices, [:organization_id, :issuing_date], algorithm: :concurrently, if_exists: true
  end
end
