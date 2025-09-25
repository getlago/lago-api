# frozen_string_literal: true

class AddCustomerSnapshotToInvoices < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.datetime :customer_data_snapshotted_at
        t.string :customer_display_name
        t.string :customer_legal_name
        t.string :customer_legal_number
        t.string :customer_email
        t.string :customer_address_line1
        t.string :customer_address_line2
        t.string :customer_city
        t.string :customer_zipcode
        t.string :customer_state
        t.string :customer_country
        t.string :customer_phone
        t.string :customer_url
        t.string :customer_tax_identification_number
        t.string :customer_applicable_timezone
        t.string :customer_firstname
        t.string :customer_lastname
      end
    end
  end
end
