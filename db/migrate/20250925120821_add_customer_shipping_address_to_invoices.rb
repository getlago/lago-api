# frozen_string_literal: true

class AddCustomerShippingAddressToInvoices < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.string :customer_shipping_address_line1
        t.string :customer_shipping_address_line2
        t.string :customer_shipping_city
        t.string :customer_shipping_state
        t.string :customer_shipping_zipcode
        t.string :customer_shipping_country
      end
    end
  end
end
