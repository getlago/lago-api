# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackService < BaseService
    include Customers::PaymentProviderFinder
    include TypedResults

    RESULTS = {
      create: BaseResult[:paystack_customer],
      update: BaseResult,
      generate_checkout_url: BaseResult,
      update_payment_method: BaseResult[:paystack_customer, :payment_method]
    }.freeze

    private

    def create(paystack_customer)
      @paystack_customer = paystack_customer
      return result unless customer

      result.paystack_customer = paystack_customer
      return result if paystack_customer.provider_customer_id? || !paystack_payment_provider

      paystack_result = create_paystack_customer
      return result if !paystack_result || !result.success?

      paystack_customer.update!(
        provider_customer_id: paystack_result.dig("data", "customer_code")
      )

      deliver_success_webhook
      result.paystack_customer = paystack_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue PaymentProviders::Paystack::Client::Error => e
      deliver_error_webhook(e)
      result.third_party_failure!(third_party: "Paystack", error_code: e.code, error_message: e.message)
    end

    def update(paystack_customer)
      @paystack_customer = paystack_customer
      return result if !paystack_payment_provider || paystack_customer.provider_customer_id.blank?

      client.update_customer(paystack_customer.provider_customer_id, update_customer_payload)
      result
    rescue PaymentProviders::Paystack::Client::Error => e
      deliver_error_webhook(e)
      result.third_party_failure!(third_party: "Paystack", error_code: e.code, error_message: e.message)
    end

    def generate_checkout_url(paystack_customer, send_webhook: true)
      @paystack_customer = paystack_customer
      result.not_allowed_failure!(code: "feature_not_supported")
    end

    def update_payment_method(organization_id:, customer_id:, payment_method_id:, metadata: {}, card_details: {})
      @paystack_customer = PaymentProviderCustomers::PaystackCustomer.find_by(customer_id:)
      return handle_missing_customer(organization_id, metadata) unless paystack_customer

      paystack_customer.authorization_code = payment_method_id
      paystack_customer.payment_method_id = payment_method_id
      paystack_customer.save!

      find_or_create_result = PaymentMethods::FindOrCreateFromProviderService.call(
        customer: paystack_customer.customer,
        payment_provider_customer: paystack_customer,
        provider_method_id: payment_method_id,
        params: {provider_payment_methods: PaymentProviderCustomers::PaystackCustomer::PAYMENT_METHODS},
        set_as_default: true
      )
      result.payment_method = find_or_create_result.payment_method

      if card_details.present? && result.payment_method.present?
        PaymentMethods::UpdateDetailsService.call(
          payment_method: result.payment_method,
          insert: card_details
        )
      end

      result.paystack_customer = paystack_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    attr_accessor :paystack_customer

    delegate :customer, to: :paystack_customer

    def create_paystack_customer
      client.create_customer(create_customer_payload)
    end

    def create_customer_payload
      {
        email: paystack_email,
        first_name: customer.firstname,
        last_name: customer.lastname,
        phone: customer.phone,
        metadata: {
          lago_customer_id: customer.id,
          customer_id: customer.external_id
        }
      }.compact
    end

    def update_customer_payload
      {
        first_name: customer.firstname,
        last_name: customer.lastname,
        phone: customer.phone,
        metadata: {
          lago_customer_id: customer.id,
          customer_id: customer.external_id
        }
      }.compact
    end

    def paystack_email
      customer.email&.strip&.split(",")&.first
    end

    def deliver_success_webhook
      SendWebhookJob.perform_later("customer.payment_provider_created", customer)
    end

    def deliver_error_webhook(paystack_error)
      SendWebhookJob.perform_later(
        "customer.payment_provider_error",
        customer,
        provider_error: {
          message: paystack_error.message,
          error_code: paystack_error.respond_to?(:code) ? paystack_error.code : nil
        }
      )
    end

    def handle_missing_customer(organization_id, metadata)
      return result unless metadata&.key?("lago_customer_id") || metadata&.key?(:lago_customer_id)

      lago_customer_id = metadata["lago_customer_id"] || metadata[:lago_customer_id]
      return result if Customer.find_by(id: lago_customer_id, organization_id:).nil?

      result.not_found_failure!(resource: "paystack_customer")
    end

    def client
      @client ||= PaymentProviders::Paystack::Client.new(payment_provider: paystack_payment_provider)
    end

    def paystack_payment_provider
      @paystack_payment_provider ||= payment_provider(customer)
    end
  end
end
