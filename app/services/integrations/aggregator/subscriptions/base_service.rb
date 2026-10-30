# frozen_string_literal: true

module Integrations
  module Aggregator
    module Subscriptions
      class BaseService < Integrations::Aggregator::BaseService
        def initialize(subscription:)
          @subscription = subscription

          super(integration:)
        end

        private

        attr_reader :subscription

        delegate :customer, to: :subscription, allow_nil: true

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.accounting_kind&.first
        end
      end
    end
  end
end
