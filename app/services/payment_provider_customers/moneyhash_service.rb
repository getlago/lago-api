# frozen_string_literal: true

module PaymentProviderCustomers
  class MoneyhashService < BaseService
    include Customers::PaymentProviderFinder

    def initialize(moneyhash_customer = nil)
      @moneyhash_customer = moneyhash_customer

      super(nil)
    end

    def create
      result.moneyhash_customer = moneyhash_customer
      return result if moneyhash_customer.provider_customer_id?
      moneyhash_result = create_moneyhash_customer

      moneyhash_customer.update!(
        provider_customer_id: moneyhash_result["data"]["id"]
      )
      deliver_success_webhook
      result.moneyhash_customer = moneyhash_customer
      result
    end

    def update
      result
    end

    private

    attr_accessor :moneyhash_customer

    delegate :customer, to: :moneyhash_customer

    def client
      @client || LagoHttpClient::Client.new("#{PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/customers/")
    end

    def api_key
      moneyhash_payment_provider.secret_key
    end

    def moneyhash_payment_provider
      @moneyhash_payment_provider ||= payment_provider(customer)
    end

    def create_moneyhash_customer
      customer_params = {
        first_name: customer&.firstname,
        last_name: customer&.lastname,
        email: customer&.email,
        phone_number: customer&.phone,
        tax_id: customer&.tax_identification_number,
        address: customer&.address_line1,
        contact_person_name: customer&.legal_name
      }.compact

      response = client.post_with_response(customer_params, headers)
      JSON.parse(response.body)
    rescue LagoHttpClient::HttpError => e
      deliver_error_webhook(e)
      raise
    end

    def deliver_error_webhook(moneyhash_error)
      SendWebhookJob.perform_later(
        'customer.payment_provider_error',
        customer,
        provider_error: {
          message: moneyhash_error.message,
          error_code: moneyhash_error.error_code
        }
      )
    end

    def deliver_success_webhook
      SendWebhookJob.perform_later(
        'customer.payment_provider_created',
        customer
      )
    end

    def headers
      {
        'Content-Type' => 'application/json',
        'x-Api-Key' => moneyhash_payment_provider.api_key
      }
    end
  end
end
