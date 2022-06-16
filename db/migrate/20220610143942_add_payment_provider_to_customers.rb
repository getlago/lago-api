# frozen_string_literal: true

class AddPaymentProviderToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :payment_provider, :string
  end
end
