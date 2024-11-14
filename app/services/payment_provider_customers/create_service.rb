# frozen_string_literal: true

module PaymentProviderCustomers
  class CreateService < BaseService
    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def create_or_update(customer_class:, payment_provider_id:, params:, async: true)
      provider_customer = customer_class.find_by(customer_id: customer.id)
      provider_customer ||= customer_class.new(customer_id: customer.id, payment_provider_id:)

      if (params || {}).key?(:provider_customer_id)
        provider_customer.provider_customer_id = params[:provider_customer_id].presence
      end

      if (params || {}).key?(:sync_with_provider)
        provider_customer.sync_with_provider = params[:sync_with_provider].presence
      end

      provider_customer = handle_provider_payment_methods(provider_customer:, params:)
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

    def handle_provider_payment_methods(provider_customer:, params:)
      return provider_customer unless provider_customer.is_a?(PaymentProviderCustomers::StripeCustomer)

      provider_payment_methods = (params || {})[:provider_payment_methods]

      if provider_customer.persisted?
        provider_customer.provider_payment_methods = provider_payment_methods if provider_payment_methods.present?
      else
        provider_customer.provider_payment_methods = provider_payment_methods.presence || %w[card]
      end

      provider_customer
    end

    def create_customer_on_provider_service(async)
      if result.provider_customer.type == 'PaymentProviderCustomers::StripeCustomer'
        return PaymentProviderCustomers::StripeCreateJob.perform_later(result.provider_customer) if async

        PaymentProviderCustomers::StripeCreateJob.perform_now(result.provider_customer)
      elsif result.provider_customer.type == 'PaymentProviderCustomers::AdyenCustomer'
        return PaymentProviderCustomers::AdyenCreateJob.perform_later(result.provider_customer) if async

        PaymentProviderCustomers::AdyenCreateJob.perform_now(result.provider_customer)
      elsif result.provider_customer.type == 'PaymentProviderCustomers::MoneyhashCustomer'
        return PaymentProviderCustomers::MoneyhashCreateJob.perform_later(result.provider_customer) if async

        PaymentProviderCustomers::MoneyhashCreateJob.perform_now(result.provider_customer)
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
      !result.provider_customer.id_previously_changed?(from: nil) && # it was not created but updated
        result.provider_customer.provider_customer_id_previously_changed? &&
        result.provider_customer.provider_customer_id? &&
        result.provider_customer.sync_with_provider.blank?
    end
  end
end
