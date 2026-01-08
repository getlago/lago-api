# frozen_string_literal: true

module PaymentMethods
  class CreateFromProviderService < BaseService
    def initialize(customer:, params:, provider_method_id:, payment_provider_id: nil, payment_provider_customer: nil)
      @customer = customer
      @params = params || {}
      @provider_method_id = provider_method_id
      @payment_provider_id = payment_provider_id
      @payment_provider_customer = payment_provider_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      payment_method = customer.payment_methods.build.tap do |payment_method|
        payment_method.organization = customer.organization
        payment_method.payment_provider_customer = payment_provider_customer
        payment_method.provider_method_type = provider_method_type
        payment_method.provider_method_id = provider_method_id
        payment_method.payment_provider_id = payment_provider_id
        payment_method.is_default = !customer.payment_methods.exists?(is_default: true)

        # payment_method.details
        payment_method.details = {}
        payment_method.details[:sync_with_provider] = !!params[:sync_with_provider] if params.key?(:sync_with_provider)
        payment_method.details[:provider_customer_id] = payment_provider_customer.provider_customer_id if payment_provider_customer.try(:provider_customer_id).present?
      end

      payment_method.save!

      result.payment_method = payment_method
      result
    end

    private

    attr_accessor :customer, :params, :provider_method_id, :payment_provider_id, :payment_provider_customer

    def provider_method_type
      if (provider_payment_methods = params[:provider_payment_methods]).present?
        Array.wrap(provider_payment_methods).first
      else
        "card"
      end
    end
  end
end
