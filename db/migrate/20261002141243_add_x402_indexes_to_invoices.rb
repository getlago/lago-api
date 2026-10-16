# frozen_string_literal: true

class AddX402IndexesToInvoices < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:invoices, nil, name: :index_invoices_on_x402_payment_token, valid: false)
      remove_index :invoices, name: :index_invoices_on_x402_payment_token, algorithm: :concurrently
    end

    if index_exists?(:invoices, nil, name: :index_invoices_on_x402_connection_id, valid: false)
      remove_index :invoices, name: :index_invoices_on_x402_connection_id, algorithm: :concurrently
    end

    add_index :invoices,
      :x402_payment_token,
      unique: true,
      where: "x402_payment_token IS NOT NULL",
      name: :index_invoices_on_x402_payment_token,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :invoices,
      :x402_connection_id,
      where: "x402_connection_id IS NOT NULL",
      name: :index_invoices_on_x402_connection_id,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :invoices, name: :index_invoices_on_x402_connection_id, algorithm: :concurrently, if_exists: true
    remove_index :invoices, name: :index_invoices_on_x402_payment_token, algorithm: :concurrently, if_exists: true
  end
end
