# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module PayloadBuilder
        def self.assign(integration:, customer:, invoice: nil, integration_customer:, fees: [], credit_note: nil, items: [])
          if credit_note.present?
            Payloads::CreditNote.new(integration:, customer:, integration_customer:, items: [], credit_note:)
          else
            Payloads::Invoice.new(integration:, customer:, invoice:, integration_customer:, fees: [])
          end
        end
      end
    end
  end
end
