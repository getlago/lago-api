# frozen_string_literal: true

module PaymentProviderCustomers
  class UpdateConnectionService < BaseService
    Result = BaseResult[:payment_provider_customer]

    def initialize(payment_provider_customer:, params:)
      @payment_provider_customer = payment_provider_customer
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_provider_customer") unless payment_provider_customer

      ActiveRecord::Base.transaction do
        payment_provider_customer.update!(code: params[:code]) if params.key?(:code)

        update_provider_customer if editing_provider_customer?
      end

      if params[:provider_customer_id].present?
        PaymentProviderCustomers::UpdateService.call(customer).raise_if_error!
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

    def provider
      @provider ||= payment_provider_customer.type.demodulize.underscore.delete_suffix("_customer")
    end

    def editing_provider_customer?
      params.key?(:provider_customer_id) ||
        params.key?(:provider_payment_methods) ||
        params.key?(:sync_with_provider)
    end

    def provider_customer_params
      @provider_customer_params ||= params.slice(:provider_customer_id, :provider_payment_methods, :sync_with_provider)
    end

    def update_provider_customer
      PaymentProviders::CreateCustomerFactory.new_instance(
        provider:,
        customer:,
        payment_provider_id: payment_provider_customer&.payment_provider&.id,
        params: provider_customer_params
      ).call!

      customer.reload
    end
  end
end
