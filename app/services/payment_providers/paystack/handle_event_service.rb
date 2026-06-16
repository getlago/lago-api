# frozen_string_literal: true

module PaymentProviders
  module Paystack
    class HandleEventService < BaseService
      CHARGE_EVENTS = %w[charge.success charge.failed].freeze
      REFUND_EVENTS = %w[refund.pending refund.processing refund.needs-attention refund.failed refund.processed refund.reversed].freeze

      PAYMENT_SERVICE_CLASS_MAP = {
        "Invoice" => Invoices::Payments::PaystackService,
        "PaymentRequest" => PaymentRequests::Payments::PaystackService
      }.freeze

      def initialize(organization:, payment_provider:, event_json:)
        @organization = organization
        @payment_provider = payment_provider
        @event_json = event_json

        super
      end

      def call
        return handle_charge_event if CHARGE_EVENTS.include?(event_type)
        return handle_refund_event if REFUND_EVENTS.include?(event_type)

        Rails.logger.warn("Unexpected paystack event type: #{event_type}")
        result
      rescue JSON::ParserError
        result.service_failure!(code: "webhook_error", message: "Invalid payload")
      rescue PaymentProviders::Paystack::Client::Error => e
        result.service_failure!(code: e.code, message: e.message)
      rescue LagoHttpClient::HttpError => e
        result.service_failure!(code: e.error_code, message: e.message)
      end

      private

      attr_reader :organization, :payment_provider, :event_json

      def handle_charge_event
        return result if event_reference.blank?

        verified_transaction = verify_transaction
        return result unless metadata_belongs_to_organization?(verified_metadata)

        if verified_metadata[:payment_type] == "setup"
          update_customer_payment_method(verified_transaction["authorization"], verified_metadata)
          return result
        end

        payable = find_payable(verified_metadata)
        return result unless payable
        return result if payable.payment_succeeded?
        return amount_mismatch_failure(payable, verified_transaction) unless amount_matches?(payable, verified_transaction)
        return currency_mismatch_failure(payable, verified_transaction) unless currency_matches?(payable, verified_transaction)

        payment_service_class(verified_metadata).new(payable).update_payment_status(
          organization_id: organization.id,
          status: verified_transaction["status"],
          paystack_payment: PaymentProviders::PaystackProvider::PaystackPayment.new(
            id: verified_transaction["id"].to_s,
            status: verified_transaction["status"],
            metadata: verified_metadata,
            authorization: verified_transaction["authorization"],
            reference: verified_transaction["reference"],
            amount: verified_transaction["amount"],
            currency: verified_transaction["currency"],
            gateway_response: verified_transaction["gateway_response"]
          )
        ).raise_if_error!

        result
      end

      def handle_refund_event
        refund_data = event["data"] || {}

        refund_result = CreditNotes::Refunds::PaystackService.new.update_status(
          provider_refund_id: refund_data["id"] || refund_data["refund_reference"],
          transaction_reference: refund_data["transaction_reference"],
          status: refund_data["status"],
          metadata: refund_data
        )
        return result if refund_result.failure? && refund_result.error.code == "refund_failed"

        refund_result.raise_if_error!

        result
      end

      def verify_transaction
        return @verified_transaction if defined?(@verified_transaction)

        response = client.verify_transaction(event_reference)
        @verified_transaction = response["data"]

        if @verified_transaction.blank?
          return result.service_failure!(code: "webhook_error", message: "Paystack verification returned no transaction").raise_if_error!
        end

        @verified_transaction
      end

      def update_customer_payment_method(authorization, metadata)
        return result unless reusable_card_authorization?(authorization)

        paystack_customer = PaymentProviderCustomers::PaystackCustomer.find_by(
          id: metadata[:lago_paystack_customer_id],
          customer_id: metadata[:lago_customer_id],
          payment_provider_id: payment_provider.id
        )
        return result unless paystack_customer

        PaymentProviderCustomers::PaystackService.new.update_payment_method(
          organization_id: organization.id,
          customer_id: paystack_customer.customer_id,
          payment_method_id: authorization["authorization_code"],
          metadata: metadata.stringify_keys,
          card_details: card_details(authorization)
        ).raise_if_error!
      end

      def reusable_card_authorization?(authorization)
        authorization.present? &&
          authorization["authorization_code"].present? &&
          authorization["reusable"] == true &&
          authorization["channel"] == "card"
      end

      def card_details(authorization)
        {
          type: "card",
          last4: authorization["last4"],
          brand: authorization["brand"].presence || authorization["card_type"],
          expiration_month: authorization["exp_month"],
          expiration_year: authorization["exp_year"],
          issuer: authorization["bank"],
          country: authorization["country_code"]
        }.compact
      end

      def metadata_belongs_to_organization?(metadata)
        return false if metadata.blank?

        if metadata[:lago_organization_id].present? && metadata[:lago_organization_id] != organization.id
          log_metadata_mismatch(metadata)
          return false
        end

        if metadata[:lago_payment_provider_id].present? && metadata[:lago_payment_provider_id] != payment_provider.id
          log_metadata_mismatch(metadata)
          return false
        end

        true
      end

      def log_metadata_mismatch(metadata)
        Rails.logger.warn(
          "Paystack webhook metadata mismatch: organization_id=#{organization.id}, " \
          "payment_provider_id=#{payment_provider.id}, metadata=#{metadata.slice(:lago_organization_id, :lago_payment_provider_id)}"
        )
      end

      def find_payable(metadata)
        case metadata[:lago_payable_type] || "Invoice"
        when "Invoice"
          Invoice.find_by(id: metadata[:lago_payable_id] || metadata[:lago_invoice_id], organization_id: organization.id)
        when "PaymentRequest"
          PaymentRequest.find_by(id: metadata[:lago_payable_id], organization_id: organization.id)
        end
      end

      def payment_service_class(metadata)
        payable_type = metadata[:lago_payable_type] || "Invoice"

        PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
          raise NameError, "Invalid lago_payable_type: #{payable_type}"
        end
      end

      def amount_matches?(payable, transaction)
        expected_amount = if payable.is_a?(Invoice)
          payable.total_due_amount_cents
        else
          payable.total_amount_cents
        end

        transaction["amount"].to_i == expected_amount.to_i
      end

      def currency_matches?(payable, transaction)
        transaction["currency"].to_s.upcase == payable.currency.to_s.upcase
      end

      def amount_mismatch_failure(payable, transaction)
        result.service_failure!(
          code: "webhook_error",
          message: "Paystack amount mismatch for #{payable.class.name} #{payable.id}: expected #{payable_amount(payable)}, got #{transaction["amount"]}"
        )
      end

      def currency_mismatch_failure(payable, transaction)
        result.service_failure!(
          code: "webhook_error",
          message: "Paystack currency mismatch for #{payable.class.name} #{payable.id}: expected #{payable.currency}, got #{transaction["currency"]}"
        )
      end

      def payable_amount(payable)
        return payable.total_due_amount_cents if payable.is_a?(Invoice)

        payable.total_amount_cents
      end

      def verified_metadata
        @verified_metadata ||= normalized_metadata(verify_transaction["metadata"] || {})
      end

      def normalized_metadata(metadata)
        parsed_metadata = if metadata.is_a?(String)
          JSON.parse(metadata)
        else
          metadata
        end

        parsed_metadata.to_h.symbolize_keys
      rescue JSON::ParserError
        {}
      end

      def event_reference
        @event_reference ||= event.dig("data", "reference")
      end

      def event_type
        @event_type ||= event["event"]
      end

      def event
        @event ||= event_json.is_a?(String) ? JSON.parse(event_json) : event_json
      end

      def client
        @client ||= PaymentProviders::Paystack::Client.new(payment_provider:)
      end
    end
  end
end
