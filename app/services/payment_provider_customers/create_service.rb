# frozen_string_literal: true

module PaymentProviderCustomers
  class CreateService < BaseService
    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def create_or_update(customer_class:, payment_provider_id:, params:, async: true)
      provider_customer = customer_class.find_or_initialize_by(
        customer_id: customer.id,
        payment_provider_id: payment_provider_id,
      )

      if (params || {}).key?(:provider_customer_id)
        provider_customer.provider_customer_id = params[:provider_customer_id].presence
      end

      provider_customer.save!

      result.provider_customer = provider_customer

      create_customer_on_provider_service(async)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :customer

    delegate :organization, to: :customer

    def create_customer_on_provider_service(async)
      # NOTE: the customer already exists on the service provider
      return if result.provider_customer.provider_customer_id?

      # NOTE: the customer id wa removed from the customer
      return if result.provider_customer.provider_customer_id_previously_changed?

      # NOTE: organization does not have stripe config or does not enforce customer creation on stripe
      return unless organization.stripe_payment_provider&.create_customers

      if async
        PaymentProviderCustomers::StripeCreateJob.perform_later(result.provider_customer)
      else
        PaymentProviderCustomers::StripeCreateJob.perform_now(result.provider_customer)
      end
    end
  end
end
