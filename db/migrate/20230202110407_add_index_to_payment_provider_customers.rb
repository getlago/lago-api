# frozen_string_literal: true

class AddIndexToPaymentProviderCustomers < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        # Remove duplicated customers before adding new index
        payment_customers = PaymentProviderCustomers::BaseCustomer.unscoped.group(:customer_id, :type)
          .having('COUNT(id) > 1')
          .select('COUNT(id) AS customer_count, customer_id, type')

        payment_customers.each do |payment_customer|
          customers = PaymentProviderCustomers::BaseCustomer.unscoped.where(
            customer_id: payment_customer.customer_id,
            type: payment_customer.type
          ).order('payment_provider_id ASC NULLS LAST, updated_at desc')

          customers[1..].each(&:destroy)
        end
      end
    end
    safety_assured do
      add_index :payment_provider_customers, %i[customer_id type], unique: true
    end
    remove_index :payment_provider_customers, :customer_id
  end
end
