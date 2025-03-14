# frozen_string_literal: true

module PaymentProviders
  module Moneyhash
    module Payments
      class CreateService < BaseService
        include ::Customers::PaymentProviderFinder

        def initialize(payment:)
          @payment = payment
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          if @invoice.invoice_type == "subscription"

            moneyhash_result = create_moneyhash_payment

            payment.provider_payment_id = moneyhash_result.dig("data", "id")
            payment.status = moneyhash_result.dig("data", "status")
            payment.payable_payment_status = payment.payment_provider&.determine_payment_status(payment.status)
            payment.save!

            result.payment = payment

          else
            result.fail_with_error!("Moneyhash supports automatic payments only for subscription invoices.")
          end

          result
        end

        private

        attr_reader :payment, :invoice, :provider_customer

        delegate :payment_provider, :customer, to: :provider_customer

        def create_moneyhash_payment
          payment_params = {
            amount: invoice.total_amount_cents / 100.0,
            amount_currency: invoice.currency.upcase,
            flow_id: moneyhash_payment_provider.flow_id,
            billing_data: {
              first_name: invoice&.customer&.firstname,
              last_name: invoice&.customer&.lastname,
              phone_number: invoice&.customer&.phone,
              email: invoice&.customer&.email
            },
            customer: provider_customer.provider_customer_id,
            webhook_url: moneyhash_payment_provider.webhook_end_point,
            merchant_initiated: true,
            recurring_data: {
              agreement_id: invoice.subscriptions&.first&.external_id
            },
            custom_fields: {
              lago_mit: true,
              lago_customer_id: invoice&.customer&.id,
              lago_payable_id: invoice.id,
              lago_payable_type: invoice.class.name,
              lago_plan_id: invoice.subscriptions&.first&.plan_id,
              lago_subscription_external_id: invoice.subscriptions&.first&.external_id,
              lago_organization_id: organization&.id,
              lago_mh_service: "PaymentProviders::Moneyhash::Payments::CreateService"
            }
          }

          response = client.post_with_response(payment_params, headers)
          JSON.parse(response.body)
        rescue LagoHttpClient::HttpError => e
          prepare_failed_result(e, reraise: true)
        end

        def client
          @client || LagoHttpClient::Client.new("#{::PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/payments/intent/")
        end

        def headers
          {
            "Content-Type" => "application/json",
            "x-Api-Key" => moneyhash_payment_provider.api_key
          }
        end

        def moneyhash_payment_provider
          @moneyhash_payment_provider ||= payment_provider(customer)
        end

        def prepare_failed_result(error, reraise: false)
          result.error_message = error.message
          result.error_code = error.code
          result.reraise = reraise

          payment.update!(status: :failed, payable_payment_status: :failed)

          result.service_failure!(code: "moneyhash_error", message: "#{error.code}: #{error.message}")
        end
      end
    end
  end
end
