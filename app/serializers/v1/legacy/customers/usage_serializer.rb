# frozen_string_literal: true

module V1
  module Legacy
    module Customers
      class UsageSerializer < ModelSerializer
        def serialize
          {
            from_date: model.from_datetime&.to_date,
            to_date: model.to_datetime&.to_date,
            amount_currency: model.currency,
            total_amount_currency: model.currency,
            vat_amount_currency: model.currency,
            vat_amount_cents: model.taxes_amount_cents
          }
        end
      end
    end
  end
end
