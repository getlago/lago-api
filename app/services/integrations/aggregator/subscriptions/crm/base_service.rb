# frozen_string_literal: true

module Integrations
  module Aggregator
    module Subscriptions
      module Crm
        class BaseService < Integrations::Aggregator::Subscriptions::BaseService
          private

          def integration_customer
            @integration_customer ||= customer&.integration_customers&.crm_kind&.first
          end
        end
      end
    end
  end
end
