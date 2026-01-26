# frozen_string_literal: true

module PaymentProviders
  module Moneyhash
    class HandleEventService < BaseService
      INTENT_WEBHOOKS_EVENTS = %w[intent.processed intent.time_expired].freeze
      TRANSACTION_WEBHOOKS_EVENTS = %w[transaction.purchase.failed transaction.purchase.pending_authentication transaction.purchase.successful].freeze
      CARD_WEBHOOKS_EVENTS = %w[card_token.created card_token.updated card_token.deleted].freeze
      ALLOWED_WEBHOOK_EVENTS = (INTENT_WEBHOOKS_EVENTS + TRANSACTION_WEBHOOKS_EVENTS + CARD_WEBHOOKS_EVENTS).freeze

      PAYMENT_SERVICE_CLASS_MAP = {
        "Invoice" => Invoices::Payments::MoneyhashService,
        "PaymentRequest" => PaymentRequests::Payments::MoneyhashService
      }.freeze

      def initialize(organization:, event_json:)
        @event_json = event_json
        @organization = organization

        super
      end

      def call
        unless ALLOWED_WEBHOOK_EVENTS.include?(event_code)
          return result.service_failure!(
            code: "webhook_error",
            message: "Invalid moneyhash event code: #{event_code}"
          )
        end

        event_handlers.fetch(event_code, method(:default_handler)).call
      end

      private

      attr_reader :organization, :event_json

      def event_code
        @event_code ||= event_json["type"]
      end

      def event_handlers
        {
          "intent.processed" => method(:handle_intent_event),
          "intent.time_expired" => method(:handle_intent_event),
          "transaction.purchase.failed" => method(:handle_transaction_event),
          "transaction.purchase.pending_authentication" => method(:handle_transaction_event),
          "transaction.purchase.successful" => method(:handle_transaction_event),
          "card_token.created" => method(:handle_card_event),
          "card_token.updated" => method(:handle_card_event),
          "card_token.deleted" => method(:handle_card_event)
        }
      end

      def payment_service_klass(event_json)
        payable_type = event_json.dig("intent", "custom_fields", "lago_payable_type") || "Invoice"
        PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
          raise NameError, "Invalid lago_payable_type: #{payable_type}"
        end
      end

      def handle_intent_event
        if INTENT_WEBHOOKS_EVENTS.include?(event_code)
          payment_service_klass(@event_json)
            .new.update_payment_status(
              organization_id: @organization.id,
              provider_payment_id: @event_json.dig("data", "intent_id"),
              status: event_to_payment_status(event_code),
              metadata: @event_json.dig("data", "intent", "custom_fields")
            ).raise_if_error!
        end
      end

      def handle_transaction_event
        if TRANSACTION_WEBHOOKS_EVENTS.include?(event_code)
          payment_service_klass(@event_json)
            .new.update_payment_status(
              organization_id: @organization.id,
              provider_payment_id: @event_json.dig("intent", "id"),
              status: event_to_payment_status(event_code),
              metadata: @event_json.dig("intent", "custom_fields")
            ).raise_if_error!
        end
      end

      def handle_card_event
        case event_code
        when "card_token.deleted"
          handle_card_token_deleted
        when "card_token.created", "card_token.updated"
          handle_card_token_created_or_updated
        end
      end

      def handle_card_token_deleted
        PaymentProviderCustomers::MoneyhashService.new
          .delete_payment_method(
            organization_id: organization.id,
            customer_id: card_token.dig("custom_fields", "lago_customer_id"),
            payment_method_id: card_token["id"],
            metadata: card_token["custom_fields"]
          ).raise_if_error!
      end

      def handle_card_token_created_or_updated
        PaymentProviderCustomers::MoneyhashService.new
          .update_payment_method(
            organization_id: organization.id,
            customer_id: card_token.dig("custom_fields", "lago_customer_id"),
            payment_method_id: card_token["id"],
            metadata: card_token["custom_fields"],
            card_details: extract_card_details
          ).raise_if_error!
      end

      def card_token
        @card_token ||= event_json.dig("data", "card_token")
      end

      def event_to_payment_status(event_code)
        # MH's event -> MH's payment status
        case event_code
        when "intent.processed", "transaction.purchase.successful"
          "SUCCESSFUL"
        when "intent.time_expired", "transaction.purchase.failed"
          "FAILED"
        when "transaction.purchase.pending_authentication"
          "PENDING"
        end
      end

      def default_handler
        result.service_failure!(
          code: "webhook_error",
          message: "No handler for event code: #{event_code}"
        )
      end

      def extract_card_details
        return {} unless card_token

        {
          brand: card_token["brand"],
          last4: card_token["last_4"],
          card_type: card_token["type"],
          expiry_month: card_token["expiry_month"],
          expiry_year: card_token["expiry_year"],
          card_holder_name: card_token["card_holder_name"],
          issuer: card_token["issuer"]
        }.compact
      end
    end
  end
end
