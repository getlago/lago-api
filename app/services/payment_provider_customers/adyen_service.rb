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

      adyen_result = generate_checkout_url

      result.checkout_url = adyen_result.response['url']
      result
    end

    def generate_checkout_url
      res = client.checkout.payment_links_api.payment_links(payment_link_params)

      SendWebhookJob.perform_later(
        'customer.checkout_url_generated',
        customer,
        checkout_url: res.response['url'],
      )

      res
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
        SendWebhookJob.perform_later('customer.payment_provider_created', customer) if organization.webhook_url?
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
        shopperReference: customer.external_id,
        storePaymentMethodMode: 'enabled',
        recurringProcessingModel: 'UnscheduledCardOnFile',
        expiresAt: Time.current + 70.days,
      }
      prms[:shopperEmail] = customer.email if customer.email
      prms
    end

    def deliver_error_webhook(adyen_error)
      return unless organization.webhook_url?

      SendWebhookJob.perform_later(
        'customer.payment_provider_error',
        customer,
        provider_error: {
          message: adyen_error.request&.dig('msg') || adyen_error.msg,
          error_code: adyen_error.request&.dig('code') || adyen_error.code,
        },
      )
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
