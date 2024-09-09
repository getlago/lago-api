# frozen_string_literal: true

class AddCustomerTypeToCustomers < ActiveRecord::Migration[7.1]
  def change
    create_enum :customer_type, %w[company individual]

    safety_assured do
      change_table :customers do |t|
        t.enum :customer_type, enum_type: 'customer_type', null: true
      end
    end
  end
end
