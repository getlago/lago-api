# frozen_string_literal: true

module V1
  module Legacy
    class InvoiceSerializer < ModelSerializer
      def serialize
        {
          amount_currency: model.currency,
          vat_amount_currency: model.currency,
          credit_amount_currency: model.currency,
          total_amount_currency: model.currency,
        }
      end
    end
  end
end
