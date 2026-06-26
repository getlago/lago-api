# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Integrations
  module Aggregator
    module Companies
      module Payloads
        class Factory
          def self.new_instance(integration:, customer:, integration_customer:, subsidiary_id:)
            case integration.type.to_s
            when "Integrations::HubspotIntegration"
              Integrations::Aggregator::Companies::Payloads::Hubspot.new(
                integration:,
                customer:,
                integration_customer:,
                subsidiary_id:
              )
            else
              raise(NotImplementedError)
            end
          end
        end
      end
    end
  end
end
