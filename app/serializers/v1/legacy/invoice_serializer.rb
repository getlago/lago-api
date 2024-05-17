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
          amount_cents: model.fees_amount_cents,
          credit_amount_cents: model.credits.sum(:amount_cents),
          vat_amount_cents: model.taxes_amount_cents,
          sub_total_vat_excluded_amount_cents: model.sub_total_excluding_taxes_amount_cents,
          sub_total_vat_included_amount_cents: model.sub_total_including_taxes_amount_cents
        }
      end

      private

      def legacy
        model.version_number < Invoice::CREDIT_NOTES_MIN_VERSION
      end
    end
  end
end
