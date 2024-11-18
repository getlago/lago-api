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

          result.not_found_failure!(resource: 'stripe_customer')
        end
      end
    end
  end
end
