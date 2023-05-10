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
      
      result.checkout_url = adyen_result.response["url"]
      result
    end

    def generate_checkout_url
      res = client.checkout.payment_links_api.payment_links(payment_link_params)

      SendWebhookJob.perform_later(
        'customer.checkout_url_generated',
        customer,
        checkout_url: res.response["url"]
      )

      res
    rescue Adyen::AdyenError => e
      deliver_error_webhook(e)

      raise
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
      )
    end

    def payment_link_params
      prms = {
        reference: "authorization customer #{customer.id}",
        amount: {
          value: 0, # pre-authorization
          currency: customer.currency.presence || "USD"
        },
        merchantAccount: adyen_payment_provider.merchant_account,
        shopperReference: customer.external_id,
        storePaymentMethodMode: "enabled",
        recurringProcessingModel: "UnscheduledCardOnFile",
        expiresAt: Time.current + 70.days
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
          message: adyen_error.msg,
          error_code: adyen_error.code,
        }
      )
    end
  end
end
