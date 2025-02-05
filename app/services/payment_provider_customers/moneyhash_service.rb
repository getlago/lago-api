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

      return result if !result.success?

      provider_customer_id = begin
        moneyhash_result["data"]["id"]
      rescue
        ""
      end

      moneyhash_customer.update!(
        provider_customer_id: provider_customer_id
      )
      deliver_success_webhook
      result.moneyhash_customer = moneyhash_customer
      checkout_url_result = generate_checkout_url
      return result unless checkout_url_result.success?
      result.checkout_url = checkout_url_result.checkout_url
      result
    end

    def update
      result
    end

    def generate_checkout_url(send_webhook: true)
      return result.not_found_failure!(resource: 'moneyhash_payment_provider') unless moneyhash_payment_provider

      response = payment_url_client.post_with_response(payment_url_params, headers)
      moneyhash_result = JSON.parse(response.body)

      return result unless moneyhash_result

      moneyhash_result_data = moneyhash_result["data"]
      result.checkout_url = moneyhash_result_data["embed_url"]

      if send_webhook
        SendWebhookJob.perform_now(
          'customer.checkout_url_generated',
          customer,
          checkout_url: result.checkout_url
        )
      end
      result
    rescue LagoHttpClient::HttpError => e
      deliver_error_webhook(e)
      result.service_failure!(code: e.error_code, message: e.message)
    end

    def update_payment_method(organization_id:, customer_id:, payment_method_id:, metadata: {})
      customer = PaymentProviderCustomers::MoneyhashCustomer.find_by(customer_id: customer_id)
      return handle_missing_customer(organization_id, metadata) unless customer

      customer.payment_method_id = payment_method_id
      customer.save!

      result.moneyhash_customer = customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :moneyhash_customer

    delegate :customer, to: :moneyhash_customer

    def client
      @client || LagoHttpClient::Client.new("#{PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/customers/")
    end

    def payment_url_client
      @payment_url_client || LagoHttpClient::Client.new("#{::PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/payments/intent/")
    end

    def api_key
      moneyhash_payment_provider.secret_key
    end

    def moneyhash_payment_provider
      @moneyhash_payment_provider ||= payment_provider(customer)
    end

    def create_moneyhash_customer
      customer_params = {
        type: customer&.customer_type&.upcase,
        first_name: customer&.firstname,
        last_name: customer&.lastname,
        email: customer&.email,
        phone_number: customer&.phone,
        tax_id: customer&.tax_identification_number,
        address: customer&.address_line1,
        contact_person_name: customer&.display_name,
        company_name: customer&.legal_name
      }.compact

      response = client.post_with_response(customer_params, headers)
      JSON.parse(response.body)
    rescue LagoHttpClient::HttpError => e
      deliver_error_webhook(e)
      nil
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

    def payment_url_params
      {
        amount: 5,
        amount_currency: customer.currency.presence || 'USD',
        flow_id: moneyhash_payment_provider.flow_id,
        expires_after_seconds: 69.days.seconds.to_i,
        billing_data: {
          first_name: customer&.firstname,
          last_name: customer&.lastname,
          phone_number: customer&.phone,
          email: customer&.email
        },
        customer: moneyhash_customer.provider_customer_id,
        webhook_url: moneyhash_payment_provider.webhook_end_point,
        merchant_initiated: false,
        tokenize_card: true,
        payment_type: "UNSCHEDULED",
        custom_fields: {
          lago_mit: false,
          lago_customer_id: moneyhash_customer.customer_id,
          lago_organization_id: moneyhash_customer&.customer&.organization&.id,
          lago_mh_service: "PaymentProviderCustomers::MoneyhashService"
        }
      }
    end

    def handle_missing_customer(organization_id, metadata)
      return result unless metadata&.key?("lago_customer_id")
      return result if Customer.find_by(id: metadata["lago_customer_id"], organization_id:).nil?

      result.not_found_failure!(resource: 'moneyhash_customer')
    end
  end
end
