# frozen_string_literal: true

module Integrations
  module NetsuiteV2
    module Customers
      class SyncService < BaseService
        Result = BaseResult[:integration_customer]

        def initialize(integration:, customer:, subsidiary_id: nil)
          @integration = integration
          @customer = customer
          @subsidiary_id = subsidiary_id
          super
        end

        def call
          return result.not_found_failure!(resource: "integration") unless integration
          result if existing_integration_customer

          integration_customer = IntegrationCustomers::NetsuiteV2Customer.create!(
            organization: integration.organization,
            integration:,
            customer:,
            subsidiary_id:,
            sync_with_provider: true
          )

          payload = Payload.new(customer:, integration_customer:).to_h

          KafkaProducerService.call!(
            integration:,
            event_type: "customer.sync",
            payload:
          )

          result.integration_customer = integration_customer
          result
        end

        private

        attr_reader :integration, :customer, :subsidiary_id

        def existing_integration_customer
          IntegrationCustomers::NetsuiteV2Customer.find_by(customer:, integration:)
        end
      end
    end
  end
end
