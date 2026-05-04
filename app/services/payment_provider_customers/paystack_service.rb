# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackService < BaseService
    include Customers::PaymentProviderFinder

    AUTHORIZATION_AMOUNTS_CENTS = {
      "NGN" => 5000,
      "GHS" => 10,
      "ZAR" => 100,
      "KES" => 300,
      "USD" => 200,
      "XOF" => 100
    }.freeze

    def initialize(paystack_customer = nil)
      @paystack_customer = paystack_customer

      super(nil)
    end

    def create
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

    def update
      return result if !paystack_payment_provider || paystack_customer.provider_customer_id.blank?

      client.update_customer(paystack_customer.provider_customer_id, update_customer_payload)
      result
    rescue PaymentProviders::Paystack::Client::Error => e
      deliver_error_webhook(e)
      result.third_party_failure!(third_party: "Paystack", error_code: e.code, error_message: e.message)
    end

    def generate_checkout_url(send_webhook: true)
      return result unless customer
      return result.not_found_failure!(resource: "paystack_payment_provider") unless paystack_payment_provider
      return unsupported_currency_result unless supported_currency?(authorization_currency)

      create if paystack_customer.provider_customer_id.blank?
      return result unless result.success?

      paystack_result = client.initialize_transaction(setup_transaction_payload)
      result.checkout_url = paystack_result.dig("data", "authorization_url")

      if send_webhook
        SendWebhookJob.perform_later("customer.checkout_url_generated", customer, checkout_url: result.checkout_url)
      end

      result
    rescue PaymentProviders::Paystack::Client::Error => e
      deliver_error_webhook(e)
      result.third_party_failure!(third_party: "Paystack", error_code: e.code, error_message: e.message)
    rescue LagoHttpClient::HttpError => e
      deliver_error_webhook(e)
      result.service_failure!(code: e.error_code, message: e.message)
    end

    def update_payment_method(organization_id:, customer_id:, payment_method_id:, metadata: {}, card_details: {})
      @paystack_customer = PaymentProviderCustomers::PaystackCustomer.find_by(customer_id:)
      return handle_missing_customer(organization_id, metadata) unless paystack_customer

      paystack_customer.authorization_code = payment_method_id
      paystack_customer.payment_method_id = payment_method_id
      paystack_customer.save!

      if paystack_customer.organization.feature_flag_enabled?(:multiple_payment_methods)
        find_or_create_result = PaymentMethods::FindOrCreateFromProviderService.call(
          customer: paystack_customer.customer,
          payment_provider_customer: paystack_customer,
          provider_method_id: payment_method_id,
          params: {
            provider_payment_methods: ["card"],
            details: card_details
          },
          set_as_default: true
        )

        result.payment_method = find_or_create_result.payment_method
      end

      result.paystack_customer = paystack_customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

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

    def setup_transaction_payload
      {
        amount: authorization_amount_cents,
        email: paystack_email,
        currency: authorization_currency,
        reference: "lago-setup-#{paystack_customer.id}-#{SecureRandom.hex(6)}",
        callback_url: success_redirect_url,
        channels: ["card"],
        metadata: {
          lago_customer_id: customer.id,
          lago_paystack_customer_id: paystack_customer.id,
          lago_payment_provider_id: paystack_payment_provider.id,
          lago_payment_provider_code: paystack_payment_provider.code,
          payment_type: "setup"
        }.to_json
      }
    end

    def paystack_email
      customer.email&.strip&.split(",")&.first
    end

    def authorization_currency
      (customer.currency.presence || customer.organization_default_currency).to_s.upcase
    end

    def authorization_amount_cents
      AUTHORIZATION_AMOUNTS_CENTS.fetch(authorization_currency)
    end

    def supported_currency?(currency)
      PaymentProviders::PaystackProvider.supported_currency?(currency)
    end

    def unsupported_currency_result
      result.single_validation_failure!(error_code: "unsupported_currency", field: :currency)
    end

    def success_redirect_url
      paystack_payment_provider.success_redirect_url.presence ||
        PaymentProviders::PaystackProvider::SUCCESS_REDIRECT_URL
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
