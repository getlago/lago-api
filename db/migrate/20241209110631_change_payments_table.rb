# frozen_string_literal: true

class ChangePaymentsTable < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    change_column_null :payments, :provider_payment_id, true

    create_enum :payment_type, %w[provider manual]

    safety_assured do
      change_table :payments, bulk: true do |t|
        t.string :reference, default: nil
        t.enum :payment_type, enum_type: 'payment_type', null: false, default: 'provider'
      end
    end
  end
end
