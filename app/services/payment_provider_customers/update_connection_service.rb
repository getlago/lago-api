# frozen_string_literal: true

module PaymentProviderCustomers
  class UpdateConnectionService < BaseService
    include Customers::PaymentProviderFinder

    Result = BaseResult[:payment_provider_customer]

    def initialize(payment_provider_customer:, params:)
      @payment_provider_customer = payment_provider_customer
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_provider_customer") unless payment_provider_customer

      ActiveRecord::Base.transaction do
        if params.key?(:code)
          payment_provider_customer.code = params[:code]
          payment_provider_customer.save!
        end

        # NOTE: provider_payment_methods only exist on Stripe connections; it is silently
        #       ignored for any other provider.
        update_provider_payment_methods if update_provider_payment_methods?
      end

      result.payment_provider_customer = payment_provider_customer.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :payment_provider_customer, :params

    delegate :customer, to: :payment_provider_customer

    def update_provider_payment_methods?
      params.key?(:provider_payment_methods) &&
        payment_provider_customer.is_a?(PaymentProviderCustomers::StripeCustomer)
    end

    # NOTE: mirrors the provider customer edition performed by Customers::UpdateService.
    #       The provider CreateService is an upsert that applies provider_payment_methods
    #       (with the Stripe model validations) on the existing connection.
    def update_provider_payment_methods
      PaymentProviders::CreateCustomerFactory.new_instance(
        provider: "stripe",
        customer:,
        payment_provider_id: payment_provider(customer)&.id,
        params: {provider_payment_methods: params[:provider_payment_methods]}
      ).call.raise_if_error!
    end
  end
end
