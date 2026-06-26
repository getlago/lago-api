# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Anrok < BasePayload
          def initialize(integration_customer:, invoice:)
            super
          end
        end
      end
    end
  end
end
