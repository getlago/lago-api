# frozen_string_literal: true

class DropRedundantInvoicesAndCustomersIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Prefix of idx_on_billing_entity_id_billing_entity_sequential_id
    remove_index :invoices, name: :index_invoices_on_billing_entity_id, algorithm: :concurrently, if_exists: true

    # Prefix of idx_on_organization_id_organization_sequential_id
    remove_index :invoices, name: :index_invoices_on_organization_id, algorithm: :concurrently, if_exists: true

    # Low selectivity (~5 enum values), never queried without organization_id
    remove_index :invoices, name: :index_invoices_on_status, algorithm: :concurrently, if_exists: true

    # Boolean column, ~50/50 selectivity, never queried without organization_id
    remove_index :invoices, name: :index_invoices_on_payment_overdue, algorithm: :concurrently, if_exists: true

    # Boolean column, low selectivity, never queried without organization_id
    remove_index :invoices, name: :index_invoices_on_self_billed, algorithm: :concurrently, if_exists: true

    # Never queried alone, only meaningful with organization_id or customer_id
    remove_index :invoices, name: :index_invoices_on_sequential_id, algorithm: :concurrently, if_exists: true

    # Prefix of index_customers_on_organization_id_and_sequential_id
    remove_index :customers, name: :index_customers_on_organization_id, algorithm: :concurrently, if_exists: true

    # Prefix of index_invoices_on_customer_id_and_sequential_id (UNIQUE)
    remove_index :invoices, name: :index_invoices_on_customer_id, algorithm: :concurrently, if_exists: true

    # No queries filter by number; ILIKE search cannot use a btree index
    remove_index :invoices, name: :index_invoices_on_number, algorithm: :concurrently, if_exists: true
  end
end
