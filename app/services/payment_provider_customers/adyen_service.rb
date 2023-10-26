# frozen_string_literal: true

module PaymentProviderCustomers
  class AdyenService < BaseService
    def initialize(adyen_customer = nil)
      @adyen_customer = adyen_customer

      super(nil)
    end

    def create
      result.adyen_customer = adyen_customer
      return result if adyen_customer.provider_customer_id?

      checkout_url_result = generate_checkout_url
      return result unless checkout_url_result.success?

      result.checkout_url = checkout_url_result.checkout_url
      result
    end

    def generate_checkout_url
      return result.not_found_failure!(resource: 'adyen_payment_provider') unless adyen_payment_provider

      res = client.checkout.payment_links_api.payment_links(Lago::Adyen::Params.new(payment_link_params).to_h)
      handle_adyen_response(res)
      return result unless result.success?

      checkout_url = res.response['url']

      SendWebhookJob.perform_later(
        'customer.checkout_url_generated',
        customer,
        checkout_url:,
      )

      result.checkout_url = checkout_url
      result
    rescue Adyen::AdyenError => e
      deliver_error_webhook(e)

      raise
    end

    def preauthorise(organization, event)
      shopper_reference = shopper_reference_from_event(event)
      payment_method_id = event.dig('additionalData', 'recurring.recurringDetailReference')

      @adyen_customer = PaymentProviderCustomers::AdyenCustomer
        .joins(:customer)
        .where(customers: { external_id: shopper_reference, organization_id: organization.id })
        .first

      return handle_missing_customer(shopper_reference) unless adyen_customer

      if event['success'] == 'true'
        adyen_customer.update!(payment_method_id:, provider_customer_id: shopper_reference)

        if organization.webhook_endpoints.any?
          SendWebhookJob.perform_later('customer.payment_provider_created', customer)
        end
      else
        deliver_error_webhook(Adyen::AdyenError.new(nil, nil, event['reason'], event['eventCode']))
      end

      result.adyen_customer = adyen_customer
      result
    end

    private

    attr_accessor :adyen_customer

    delegate :customer, to: :adyen_customer

    def organization
      @organization ||= customer.organization
    end

    def adyen_payment_provider
      @adyen_payment_provider || organization.adyen_payment_provider
    end

    def client
      @client ||= Adyen::Client.new(
        api_key: adyen_payment_provider.api_key,
        env: adyen_payment_provider.environment,
        live_url_prefix: adyen_payment_provider.live_prefix,
      )
    end

    def shopper_reference_from_event(event)
      event.dig('additionalData', 'shopperReference') ||
        event.dig('additionalData', 'recurring.shopperReference')
    end

    def payment_link_params
      prms = {
        reference: "authorization customer #{customer.external_id}",
        amount: {
          value: 0, # pre-authorization
          currency: customer.currency.presence || 'USD',
        },
        merchantAccount: adyen_payment_provider.merchant_account,
        returnUrl: success_redirect_url,
        shopperReference: customer.external_id,
        storePaymentMethodMode: 'enabled',
        recurringProcessingModel: 'UnscheduledCardOnFile',
        expiresAt: Time.current + 70.days,
      }
      prms[:shopperEmail] = customer.email if customer.email
      prms
    end

    def success_redirect_url
      adyen_payment_provider.success_redirect_url.presence || PaymentProviders::AdyenProvider::SUCCESS_REDIRECT_URL
    end

    def deliver_error_webhook(adyen_error)
      return unless organization.webhook_endpoints.any?

      SendWebhookJob.perform_later(
        'customer.payment_provider_error',
        customer,
        provider_error: {
          message: adyen_error.request&.dig('msg') || adyen_error.msg,
          error_code: adyen_error.request&.dig('code') || adyen_error.code,
        },
      )
    end

    def handle_adyen_response(res)
      return if res.status < 400

      code = res.response['errorType']
      message = res.response['message']

      deliver_error_webhook(Adyen::AdyenError.new(nil, nil, message, code))
      result.service_failure!(code:, message:)
    end

    def handle_missing_customer(shopper_reference)
      # NOTE: Adyen customer was not created from lago
      return result unless shopper_reference

      # NOTE: Customer does not belong to this lago instance
      return result if Customer.find_by(external_id: shopper_reference).nil?

      result.not_found_failure!(resource: 'adyen_customer')
    end
  end
end
