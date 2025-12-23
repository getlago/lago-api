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
        service = PaymentProviderCustomers::MoneyhashService.new

        case event_code
        when "card_token.deleted"
          payment_method_id = @event_json.dig("data", "card_token", "id")
          customer_id = @event_json.dig("data", "card_token", "custom_fields", "lago_customer_id")
          customer = PaymentProviderCustomers::MoneyhashCustomer.find_by(customer_id: customer_id)

          selected_payment_method_id = (customer&.payment_method_id&.present? && (customer&.payment_method_id == payment_method_id)) ? nil : customer&.payment_method_id
          service
            .update_payment_method(
              organization_id: @organization.id,
              customer_id: customer_id,
              payment_method_id: selected_payment_method_id,
              metadata: @event_json.dig("data", "card_token", "custom_fields")
            ).raise_if_error!

        when "card_token.created", "card_token.updated"
          service
            .update_payment_method(
              organization_id: @organization.id,
              customer_id: @event_json.dig("data", "card_token", "custom_fields", "lago_customer_id"),
              payment_method_id: @event_json.dig("data", "card_token", "id"),
              metadata: @event_json.dig("data", "card_token", "custom_fields")
            ).raise_if_error!
        end
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
    end
  end
end
