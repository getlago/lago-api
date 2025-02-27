# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Webhooks
      class BaseService < BaseService
        def initialize(organization_id:, event:)
          @organization = Organization.find(organization_id)
          @event = event

          super
        end

        private

        attr_reader :organization, :event

        PAYMENT_SERVICE_CLASS_MAP = {
          "Invoice" => Invoices::Payments::StripeService,
          "PaymentRequest" => PaymentRequests::Payments::StripeService
        }.freeze

        def metadata
          @metadata ||= event.data.object.metadata.to_h.symbolize_keys
        end

        def handle_missing_customer
          # NOTE: Stripe customer was not created from lago
          return result unless metadata&.key?(:lago_customer_id)

          # NOTE: Customer does not belong to this lago instance or
          #       exists but does not belong to the organizations
          #       (Happens when the Stripe API key is shared between organizations)
          return result if Customer.find_by(id: metadata[:lago_customer_id], organization_id: organization.id).nil?

          result.not_found_failure!(resource: "stripe_customer")
        end

        # TODO: Move this to a proper factory
        def payment_service_klass
          payable_type = metadata[:lago_payable_type] || "Invoice"

          PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
            raise NameError, "Invalid lago_payable_type: #{payable_type}"
          end
        end

        def update_payment_status!(status)
          payment_service_klass.new.update_payment_status(
            organization_id: organization.id,
            status:,
            stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
              id: event.data.object.id,
              status: event.data.object.status,
              metadata:
            )
          ).raise_if_error!
        end
      end
    end
  end
end
