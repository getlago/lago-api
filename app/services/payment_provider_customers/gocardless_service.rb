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
      PaymentProviderCustomers::GocardlessCheckoutUrlJob.perform_later(gocardless_customer)

      result.gocardless_customer = gocardless_customer
      result
    end

    def generate_checkout_url
      billing_request = create_billing_request(gocardless_customer.provider_customer_id)
      billing_request_flow = create_billing_request_flow(billing_request.id)

      SendWebhookJob.perform_later(
        :payment_provider_customer_checkout_url,
        customer,
        checkout_url: billing_request_flow.authorisation_url
      )
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

    def client
      @client || GoCardlessPro::Client.new(access_token: access_token, environment: :sandbox)
    end

    def create_gocardless_customer
      client.customers.create(
        params: {
          email: customer.email,
          company_name: customer.name,
        }
      )
    rescue GoCardlessPro::Error => e
      deliver_error_webhook(e)

      raise
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

    def create_billing_request(gocardless_customer_id)
      client.billing_requests.create(
        params: {
          mandate_request: {
            scheme: 'bacs',
          },
          links: {
            customer: gocardless_customer_id,
          }
        }
      )
    rescue GoCardlessPro::Error => e
      deliver_error_webhook(e)

      raise
    end

    def create_billing_request_flow(billing_request_id)
      client.billing_request_flows.create(
        params: {
          redirect_uri: 'https://gocardless.com/',
          exit_uri: 'https://gocardless.com/',
          links: {
            billing_request: billing_request_id,
          }
        }
      )
    rescue GoCardlessPro::Error => e
      deliver_error_webhook(e)

      raise
    end
  end
end
