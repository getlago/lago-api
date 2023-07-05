class UpdateProviderPaymentMethodsForStripeCustomers < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        execute(<<~SQL.squish)
          UPDATE payment_provider_customers
          SET settings['provider_payment_methods'] = '["card"]'
          WHERE type = 'PaymentProviderCustomers::StripeCustomer';
        SQL
      end
    end
  end
end
