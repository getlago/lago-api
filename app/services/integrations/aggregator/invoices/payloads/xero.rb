# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Xero < BasePayload
          def initialize(integration_customer:, invoice:)
            super
          end
        end
      end
    end
  end
end
