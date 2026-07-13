# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        OneOffFee = Data.define(:add_on_id, :item_id, :sub_total_excluding_taxes_amount_cents) do
          def id = nil

          def item_key = nil

          def units = nil

          def amount_cents = nil

          def charge? = false

          def fixed_charge? = false

          def commitment? = false

          def subscription? = false
        end
      end
    end
  end
end
