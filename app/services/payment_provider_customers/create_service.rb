# frozen_string_literal: true

module PaymentProviderCustomers
  class CreateService < BaseService
    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def create(params:)
      provider_customer = PaymentProviderCustomers::StripeCustomer.find_or_initialize_by(
        customer_id: customer.id,
        # TODO: attache payment provider of the organization
      )
      provider_customer.provider_customer_id = params[:provider_customer_id]
      # TODO: Handle settings and create customer on stripe if no customer id

      provider_customer.save!

      result.provider_customer = provider_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :customer
  end
end
