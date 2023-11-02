# frozen_string_literal: true

module V1
  module Legacy
    class FeeSerializer < ModelSerializer
      def serialize
        {
          vat_amount_cents: model.taxes_amount_cents,
          vat_amount_currency: model.currency,
          unit_amount_cents: model.unit_amount_cents,
        }
      end
    end
  end
end
