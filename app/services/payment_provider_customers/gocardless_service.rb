# frozen_string_literal: true

module PaymentProviderCustomers
  class GocardlessService < BaseService
    def initialize(gocardless_customer = nil)
      @gocardless_customer = gocardless_customer

      super(nil)
    end

    def create
      result.gocardless_customer = gocardless_customer
      return result if gocardless_customer.provider_customer_id?

      gocardless_result = create_gocardless_customer

      gocardless_customer.update!(
        provider_customer_id: gocardless_result.id,
      )

      deliver_success_webhook

      result.gocardless_customer = gocardless_customer
      result
    end

    private

    attr_accessor :gocardless_customer

    delegate :customer, to: :gocardless_customer

    def organization
      @organization ||= customer.organization
    end

    def access_token
      organization.gocardless_payment_provider.access_token
    end

    def create_gocardless_customer
      GoCardlessPro::Client
        .new(access_token: access_token, environment: :sandbox)
        .customers
        .create(params: gocardless_create_payload)
    rescue GoCardlessPro::Error => e
      deliver_error_webhook(e)

      raise
    end

    def gocardless_create_payload
      {
        email: customer.email,
        company_name: customer.name,
      }
    end

    def deliver_success_webhook
      return unless organization.webhook_url?

      SendWebhookJob.perform_later(
        :payment_provider_customer_created,
        customer,
      )
    end

    def deliver_error_webhook(gocardless_error)
      return unless organization.webhook_url?

      SendWebhookJob.perform_later(
        :payment_provider_customer_error,
        customer,
        provider_error: {
          message: gocardless_error.message,
          error_code: gocardless_error.code,
        },
      )
    end
  end
end
