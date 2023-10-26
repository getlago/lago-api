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
        payment_provider_id:,
      )

      if (params || {}).key?(:provider_customer_id)
        provider_customer.provider_customer_id = params[:provider_customer_id].presence
      end

      if (params || {}).key?(:sync_with_provider)
        provider_customer.sync_with_provider = params[:sync_with_provider].presence
      end

      if provider_customer.is_a?(PaymentProviderCustomers::StripeCustomer)
        if provider_customer.persisted? && (provider_payment_methods = (params || {})[:provider_payment_methods]).present?
          provider_customer.provider_payment_methods = provider_payment_methods
        elsif (provider_payment_methods = (params || {})[:provider_payment_methods]).present?
          provider_customer.provider_payment_methods = provider_payment_methods
        else
          provider_customer.provider_payment_methods = %w[card]
        end
      end

      provider_customer.save!

      result.provider_customer = provider_customer

      if should_create_provider_customer?
        create_customer_on_provider_service(async)
      elsif should_generate_checkout_url?
        generate_checkout_url(async)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :customer

    delegate :organization, to: :customer

    def create_customer_on_provider_service(async)
      if result.provider_customer.type == 'PaymentProviderCustomers::StripeCustomer'
        return PaymentProviderCustomers::StripeCreateJob.perform_later(result.provider_customer) if async

        PaymentProviderCustomers::StripeCreateJob.perform_now(result.provider_customer)
      elsif result.provider_customer.type == 'PaymentProviderCustomers::AdyenCustomer'
        return PaymentProviderCustomers::AdyenCreateJob.perform_later(result.provider_customer) if async

        PaymentProviderCustomers::AdyenCreateJob.perform_now(result.provider_customer)
      else
        return PaymentProviderCustomers::GocardlessCreateJob.perform_later(result.provider_customer) if async

        PaymentProviderCustomers::GocardlessCreateJob.perform_now(result.provider_customer)
      end
    end

    def generate_checkout_url(async)
      job_class = result.provider_customer.type.gsub(/Customer\z/, 'CheckoutUrlJob').constantize

      if async
        job_class.perform_later(result.provider_customer)
      else
        job_class.new.perform(result.provider_customer)
      end
    end

    def should_create_provider_customer?
      # NOTE: the customer does not exists on the service provider
      # and the customer id was not removed from the customer
      # customer sync with provider setting is set to true
      !result.provider_customer.provider_customer_id? &&
        !result.provider_customer.provider_customer_id_previously_changed? &&
        result.provider_customer.sync_with_provider.present?
    end

    def should_generate_checkout_url?
      result.provider_customer.provider_customer_id? && result.provider_customer.sync_with_provider.blank?
    end
  end
end
