# frozen_string_literal: true

class AddUniqueIndexOnInvoiceSequentialId < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index(:invoices, %i[customer_id sequential_id], unique: true, algorithm: :concurrently)
  end
end
