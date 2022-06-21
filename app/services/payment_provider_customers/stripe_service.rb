# frozen_string_literal: true

module PaymentProviderCustomers
  class StripeService < BaseService
    def initialize(stripe_customer)
      @stripe_customer = stripe_customer

      super(nil)
    end

    def create
      result.stripe_customer = stripe_customer
      return result if stripe_customer.provider_customer_id?

      stripe_result = Stripe::Customer.create(
        stripe_create_payload,
        { api_key: api_key },
      )

      stripe_customer.update!(
        provider_customer_id: stripe_result.id,
      )

      result.stripe_customer = stripe_customer
      result
    end

    private

    attr_accessor :stripe_customer

    delegate :customer, to: :stripe_customer

    def organization
      customer.organization
    end

    def api_key
      organization.stripe_payment_provider.secret_key
    end

    def stripe_create_payload
      {
        address: {
          city: customer.city,
          country: customer.country,
          line1: customer.address_line1,
          line2: customer.address_line2,
          postal_code: customer.zipcode,
          state: customer.state,
        },
        email: customer.email,
        name: customer.name,
        metadata: {
          lago_customer_id: customer.id,
          customer_id: customer.customer_id,
        },
        phone: customer.phone,
      }
    end
  end
end
