# frozen_string_literal: true

module V1
  module Legacy
    class CustomerUsageSerializer < ModelSerializer
      def serialize
        {
          from_date: model.from_datetime&.to_date,
          to_date: model.to_datetime&.to_date,
          amount_currency: currency,
          total_amount_currency: currency,
          vat_amount_currency: currency,
          vat_amount_cents:,
        }
      end

      # TODO(cache): Remove after full refresh of cache
      def currency
        model.currency || model.amount_currency
      end

      # TODO(cache): Remove after full refresh of cache
      def vat_amount_cents
        model.taxes_amount_cents || model.vat_amount_cents
      end
    end
  end
end
