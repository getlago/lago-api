# frozen_string_literal: true

class AddShippingAddressToCustomers < ActiveRecord::Migration[7.1]
  safety_assured do
    change_table :customers, bulk: true do |t|
      t.string :shipping_address_line1
      t.string :shipping_address_line2
      t.string :shipping_city
      t.string :shipping_zipcode
      t.string :shipping_state
      t.string :shipping_country
    end
  end
end
