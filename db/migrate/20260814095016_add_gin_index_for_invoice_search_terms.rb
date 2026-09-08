# frozen_string_literal: true

class AddGinIndexForInvoiceSearchTerms < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :invoices, "organization_id, search_terms gin_trgm_ops", using: :gin, algorithm: :concurrently, if_not_exists: true
  end
end
