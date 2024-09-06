# frozen_string_literal: true

class AddFirstnameAndLastnameToCustomers < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      change_table :customers, bulk: true do |t|
        t.string :firstname
        t.string :lastname
      end
    end
  end
end