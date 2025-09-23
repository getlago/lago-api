# frozen_string_literal: true

class AddCustomerSnapshotToInvoices < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :invoices, :customer_name, :string
    add_column :invoices, :customer_legal_name, :string
    add_column :invoices, :customer_legal_number, :string
    add_column :invoices, :customer_email, :string
    add_column :invoices, :customer_address_line1, :string
    add_column :invoices, :customer_address_line2, :string
    add_column :invoices, :customer_city, :string
    add_column :invoices, :customer_zipcode, :string
    add_column :invoices, :customer_state, :string
    add_column :invoices, :customer_country, :string
    add_column :invoices, :customer_phone, :string
    add_column :invoices, :customer_url, :string
    add_column :invoices, :customer_tax_identification_number, :string
    add_column :invoices, :customer_timezone, :string
    add_column :invoices, :customer_firstname, :string
    add_column :invoices, :customer_lastname, :string
    add_column :invoices, :customer_metadata, :jsonb
  end
end
