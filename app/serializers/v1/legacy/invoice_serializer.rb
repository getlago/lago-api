# frozen_string_literal: true

module V1
  module Legacy
    class InvoiceSerializer < ModelSerializer
      def serialize
        {
          legacy:,
          amount_currency: model.currency,
          vat_amount_currency: model.currency,
          credit_amount_currency: model.currency,
          total_amount_currency: model.currency,
        }
      end

      private

      def legacy
        model.version_number < Invoice::CREDIT_NOTES_MIN_VERSION
      end
    end
  end
end
