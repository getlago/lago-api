# frozen_string_literal: true

module PaymentProviderCustomers
  class CreateService < BaseService
    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def create_or_update(customer_class:, payment_provider_id:, params:)
      provider_customer = customer_class.find_or_initialize_by(
        customer_id: customer.id,
        payment_provider_id: payment_provider_id,
      )

      if params.key?(:provider_customer_id)
        provider_customer.provider_customer_id = params[:provider_customer_id]
      end

      provider_customer.save!

      result.provider_customer = provider_customer

      create_customer_on_provider_service

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :customer

    delegate :organization, to: :customer

    def create_customer_on_provider_service
      # NOTE: the customer already exists on the service provider
      return if result.provider_customer.provider_customer_id?

      # NOTE: organization does not have stripe config or does not enforce customer creation on stripe
      return unless organization.stripe_payment_provider&.create_customers

      PaymentProviderCustomers::StripeCreateJob.perform_later(result.provider_customer)
    end
  end
end
