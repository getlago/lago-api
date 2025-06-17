# frozen_string_literal: true

class UpdateProviderPaymentMethodsForStripeCustomers < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      reversible do |dir|
        dir.up do
          execute(<<~SQL.squish)
            UPDATE payment_provider_customers
            SET settings = jsonb_set(settings, '{provider_payment_methods}', '["card"]')
            WHERE type = 'PaymentProviderCustomers::StripeCustomer';
          SQL
        end
      end
    end
  end
end
