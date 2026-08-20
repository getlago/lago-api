# frozen_string_literal: true

module PaymentProviderCustomers
  class CreateConnectionService < BaseService
    Result = BaseResult[:payment_provider_customer]

    def initialize(customer:, params:)
      @customer = customer
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result.single_validation_failure!(field: :payment_provider, error_code: "value_is_mandatory") if provider_type.blank?
      return result unless create_provider_customer?

      payment_provider = find_payment_provider
      first_connection = customer.payment_provider_customers.none?

      ActiveRecord::Base.transaction do
        @payment_provider_customer = create_provider_customer(payment_provider)

        payment_provider_customer.code = params[:code] if params[:code].present?
        payment_provider_customer.is_default = true if first_connection
        payment_provider_customer.save!

        if payment_provider_customer.is_default? && customer.payment_provider.blank?
          customer.update!(payment_provider: provider_type, payment_provider_code: payment_provider.code)
        end
      end

      result.payment_provider_customer = payment_provider_customer.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :customer, :params, :payment_provider_customer

    def provider_type
      params[:payment_provider].presence
    end

    def find_payment_provider
      PaymentProviders::FindService.call!(
        organization_id: customer.organization_id,
        code: params[:payment_provider_code].presence,
        payment_provider_type: provider_type
      ).payment_provider
    end

    def create_provider_customer?
      params[:sync_with_provider] || params[:provider_customer_id]
    end

    def provider_customer_params
      @provider_customer_params ||= params.slice(:provider_customer_id, :provider_payment_methods, :sync_with_provider)
    end

    def create_provider_customer(payment_provider)
      PaymentProviders::CreateCustomerFactory.new_instance(
        provider: provider_type,
        customer:,
        payment_provider_id: payment_provider.id,
        params: provider_customer_params
      ).call!.provider_customer
    end
  end
end
