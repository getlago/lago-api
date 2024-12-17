# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    module Payments
      class CreateService < BaseService
        class MandateNotFoundError < StandardError
          DEFAULT_MESSAGE = "No mandate available for payment"
          ERROR_CODE = "no_mandate_error"

          def initialize(msg = DEFAULT_MESSAGE)
            super
          end

          def code
            ERROR_CODE
          end
        end

        def initialize(payment:)
          @payment = payment
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        PENDING_STATUSES = %w[pending_customer_approval pending_submission submitted confirmed]
          .freeze
        SUCCESS_STATUSES = %w[paid_out].freeze
        FAILED_STATUSES = %w[cancelled customer_approval_denied failed charged_back].freeze

        def call
          result.payment = payment

          gocardless_result = create_gocardless_payment

          payment.provider_payment_id = gocardless_result.id
          payment.status = gocardless_result.status
          payment.payable_payment_status = payment_status_mapping(payment.status)
          payment.save!

          result.payment = payment
          result
        rescue GoCardlessPro::ValidationError => e
          prepare_failed_result(e)
        rescue MandateNotFoundError, GoCardlessPro::Error => e
          prepare_failed_result(e, reraise: true)
        end

        attr_reader :payment, :invoice, :provider_customer

        delegate :payment_provider, :customer, to: :provider_customer

        def client
          @client ||= GoCardlessPro::Client.new(
            access_token: payment_provider.access_token,
            environment: payment_provider.environment
          )
        end

        def mandate_id
          result = client.mandates.list(
            params: {
              customer: provider_customer.provider_customer_id,
              status: %w[pending_customer_approval pending_submission submitted active]
            }
          )

          mandate = result&.records&.first

          raise MandateNotFoundError unless mandate

          provider_customer.provider_mandate_id = mandate.id
          provider_customer.save!

          mandate.id
        end

        def create_gocardless_payment
          client.payments.create(
            params: {
              amount: payment.amount_cents,
              currency: payment.amount_currency.upcase,
              retry_if_possible: false,
              metadata: {
                lago_customer_id: customer.id,
                lago_invoice_id: invoice.id,
                invoice_issuing_date: invoice.issuing_date.iso8601
              },
              links: {
                mandate: mandate_id
              }
            },
            headers: {
              "Idempotency-Key" => "payment-#{payment.id}"
            }
          )
        end

        def payment_status_mapping(payment_status)
          return :pending if PENDING_STATUSES.include?(payment_status)
          return :succeeded if SUCCESS_STATUSES.include?(payment_status)
          return :failed if FAILED_STATUSES.include?(payment_status)

          payment_status
        end

        def prepare_failed_result(error, reraise: false)
          result.error_message = error.message
          result.error_code = error.code
          result.reraise = reraise

          payment.update!(status: :failed, payable_payment_status: :failed)

          result.service_failure!(code: "gocardless_error", message: "#{error.code}: #{error.message}")
        end
      end
    end
  end
end
