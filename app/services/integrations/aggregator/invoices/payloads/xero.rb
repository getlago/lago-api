# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Payloads
        class Xero < BasePayload
          def initialize(integration_customer:, invoice:)
            super
          end

          def item(fee)
            base_item = super
            base_item["item_code"] = base_item.delete("external_id")

            if fee.precise_unit_amount.round(2) != fee.precise_unit_amount
              base_item["units"] = 1
              base_item.delete("precise_unit_amount")
              base_item["amount_cents"] = fee.amount_cents
            end

            base_item
          end

          def discounts
            discounts = super

            discounts.each do |discount|
              discount["item_code"] = discount.delete("external_id")
            end
          end
        end
      end
    end
  end
end
