# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    class HandleEventService < BaseService
      PAYMENT_ACTIONS = %w[paid_out failed cancelled customer_approval_denied charged_back].freeze
      REFUND_ACTIONS = %w[created funds_returned paid refund_settled failed].freeze

      PAYMENT_SERVICE_CLASS_MAP = {
        "Invoice" => Invoices::Payments::GocardlessService,
        "PaymentRequest" => PaymentRequests::Payments::GocardlessService
      }.freeze

      def initialize(event_json:)
        @event_json = event_json

        super
      end

      def call
        case event.resource_type
        when 'payments'
          if PAYMENT_ACTIONS.include?(event.action)
            payment_service_klass(event)
              .new.update_payment_status(
                provider_payment_id: event.links.payment,
                status: event.action
              ).raise_if_error!
          end
        when 'refunds'
          if REFUND_ACTIONS.include?(event.action)
            CreditNotes::Refunds::GocardlessService
              .new.update_status(
                provider_refund_id: event.links.refund,
                status: event.action,
                metadata: event.metadata
              ).raise_if_error!
          end
        end

        result
      end

      private

      attr_reader :organization, :event_json

      def event
        @event ||= GoCardlessPro::Resources::Event.new(JSON.parse(event_json))
      end

      def payment_service_klass(event)
        payable_type = event.metadata["lago_payable_type"] || "Invoice"

        PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
          raise NameError, "Invalid lago_payable_type: #{payable_type}"
        end
      end
    end
  end
end
