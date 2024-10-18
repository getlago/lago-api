# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Crm
        class BaseService < Integrations::Aggregator::Invoices::BaseService
          private

          def integration_customer
            @integration_customer ||= customer&.integration_customers&.crm_kind&.first
          end

          def payload
            Integrations::Aggregator::Invoices::Payloads::Factory.new_instance(integration_customer:, invoice:)
          end
        end
      end
    end
  end
end
