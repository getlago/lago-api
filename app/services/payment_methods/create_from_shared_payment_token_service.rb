# frozen_string_literal: true

module PaymentMethods
  class CreateFromSharedPaymentTokenService < BaseService
    Result = BaseResult[:payment_method, :params]

    include Customers::PaymentProviderFinder

    def initialize(customer:, params:)
      @customer = customer
      @params = (params || {}).to_h.symbolize_keys

      super
    end

    def call
      result.params = params
      return result if shared_payment_token.blank?

      if params[:payment_method_id].present? || params[:payment_method_type].present? && params[:payment_method_type].to_s != "provider"
        return result.single_validation_failure!(field: :payment_method, error_code: "invalid_payment_method")
      end

      unless PaymentMethod::SHARED_PAYMENT_TOKEN_FORMAT.match?(shared_payment_token)
        return result.single_validation_failure!(field: :payment_method, error_code: "value_is_invalid")
      end

      unless provider_customer.is_a?(PaymentProviderCustomers::StripeCustomer) && provider_customer.shared_payment_token_only?
        return result.single_validation_failure!(field: :payment_method, error_code: "invalid_payment_method")
      end

      if provider_customer.provider_customer_id.blank?
        return result.single_validation_failure!(field: :payment_method, error_code: "stripe_customer_not_created")
      end

      result.payment_method = customer.payment_methods.create!(
        organization: customer.organization,
        payment_provider: provider_customer.payment_provider,
        payment_provider_customer: provider_customer,
        provider_method_type: "shared_payment_token",
        provider_method_id: shared_payment_token,
        is_default: false,
        details: {}
      )
      result.params = {payment_method_type: "provider", payment_method_id: result.payment_method.id}

      result
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :payment_method, error_code: "value_already_exist")
    end

    private

    attr_reader :customer, :params

    def shared_payment_token
      params[:shared_payment_token]
    end

    def provider_customer
      return @provider_customer if defined?(@provider_customer)

      provider = payment_provider(customer)
      @provider_customer = provider && customer.payment_provider_customers.find_by(payment_provider_id: provider.id)
    end
  end
end
