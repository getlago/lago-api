# frozen_string_literal: true

class AddMetadataToCustomers < ActiveRecord::Migration[7.0]
  def change
    change_table :customers do |t|
      t.string :country
      t.string :address_line1
      t.string :address_line2
      t.string :state
      t.string :zipcode
      t.string :email
      t.string :city
      t.string :url
      t.string :phone
      t.string :logo_url
      t.string :legal_name
      t.string :legal_number
    end
  end
end
