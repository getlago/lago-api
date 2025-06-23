# frozen_string_literal: true

class AddInvoiceFieldsToOrganizations < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :organizations, bulk: true do |t|
        t.string :country
        t.string :address_line1
        t.string :address_line2
        t.string :state
        t.string :zipcode
        t.string :email
        t.string :city
        t.string :logo
        t.string :legal_name
        t.string :legal_number
        t.text :invoice_footer
      end
    end
  end
end
