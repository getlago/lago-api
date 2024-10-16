# frozen_string_literal: true

class AddProviderPaymentDataToPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :payments, :provider_payment_data, :jsonb, default: {}
  end
end
