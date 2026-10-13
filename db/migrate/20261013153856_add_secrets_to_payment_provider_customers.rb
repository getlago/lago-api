# frozen_string_literal: true

class AddSecretsToPaymentProviderCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_provider_customers, :secrets, :string, if_not_exists: true
  end
end
