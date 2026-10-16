# frozen_string_literal: true

class AddPaymentMethodTypeToContracts < ActiveRecord::Migration[8.0]
  def change
    create_enum :contract_payment_method_type, %w[provider manual]
    add_column :contracts, :payment_method_type, :enum, enum_type: :contract_payment_method_type, default: "provider", null: false
  end
end
