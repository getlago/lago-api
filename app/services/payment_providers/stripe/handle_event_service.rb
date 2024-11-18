# frozen_string_literal: true

module PaymentProviders
  module Stripe
    class HandleEventService < BaseService
      EVENT_MAPPING = {
        'setup_intent.succeeded' => PaymentProviders::Stripe::Webhooks::SetupIntentSucceededService,
        'customer.updated' => PaymentProviders::Stripe::Webhooks::CustomerUpdatedService,
        'charge.dispute.closed' => PaymentProviders::Stripe::Webhooks::ChargeDisputeClosedService
      }.freeze

      PAYMENT_SERVICE_CLASS_MAP = {
        "Invoice" => Invoices::Payments::StripeService,
        "PaymentRequest" => PaymentRequests::Payments::StripeService
      }.freeze

      def initialize(organization:, event_json:)
        @organization = organization
        @event_json = event_json

        super
      end

      def call
        unless PaymentProviders::StripeProvider::WEBHOOKS_EVENTS.include?(event.type)
          Rails.logger.warn("Unexpected stripe event type: #{event.type}")
          return result
        end

        if EVENT_MAPPING[event.type].present?
          EVENT_MAPPING[event.type].call(
            organization_id: organization.id,
            event:
          ).raise_if_error!

          return result
        end

        case event.type
        when 'charge.succeeded'
          payment_service_klass(event)
            .new.update_payment_status(
              organization_id: organization.id,
              status: 'succeeded',
              stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
                id: event.data.object.payment_intent,
                status: event.data.object.status,
                metadata: event.data.object.metadata.to_h.symbolize_keys
              )
            ).raise_if_error!
        when 'payment_intent.payment_failed', 'payment_intent.succeeded'
          status = (event.type == 'payment_intent.succeeded') ? 'succeeded' : 'failed'
          payment_service_klass(event)
            .new.update_payment_status(
              organization_id: organization.id,
              status:,
              stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
                id: event.data.object.id,
                status: event.data.object.status,
                metadata: event.data.object.metadata.to_h.symbolize_keys
              )
            ).raise_if_error!
        when 'payment_method.detached'
          PaymentProviderCustomers::StripeService
            .new
            .delete_payment_method(
              organization_id: organization.id,
              stripe_customer_id: event.data.object.customer,
              payment_method_id: event.data.object.id,
              metadata: event.data.object.metadata.to_h.symbolize_keys
            ).raise_if_error!
        when 'charge.refund.updated'
          CreditNotes::Refunds::StripeService
            .new.update_status(
              provider_refund_id: event.data.object.id,
              status: event.data.object.status,
              metadata: event.data.object.metadata.to_h.symbolize_keys
            )
        end
      rescue BaseService::NotFoundFailure => e
        # NOTE: Error with stripe sandbox should be ignord
        raise if event.livemode

        Rails.logger.warn("Stripe resource not found: #{e.message}. JSON: #{event_json}")
        BaseService::Result.new # NOTE: Prevents error from being re-raised
      end

      private

      attr_reader :organization, :body, :event_json

      def event
        @event ||= ::Stripe::Event.construct_from(JSON.parse(event_json))
      end

      def payment_service_klass(event)
        payable_type = event.data.object.metadata.to_h[:lago_payable_type] || "Invoice"

        PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
          raise NameError, "Invalid lago_payable_type: #{payable_type}"
        end
      end
    end
  end
end
