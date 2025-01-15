# frozen_string_literal: true

class AddAccountTypeToCustomers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    create_enum :account_type, %w[customer partner]

    safety_assured do
      change_table :customers do |t|
        t.enum :account_type, enum_type: 'account_type', null: false, default: 'customer'
      end
    end

    add_index :customers, :account_type, algorithm: :concurrently
  end
end
