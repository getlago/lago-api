# frozen_string_literal: true

module V1
  module Legacy
    class FeeSerializer < ModelSerializer
      def serialize
        {
          vat_amount_cents: model.taxes_amount_cents,
          vat_amount_currency: model.currency,
          unit_amount_cents: model.unit_amount_cents,
          lago_group_id: model.group_id,
          item: {
            group_invoice_display_name: model.charge_filter&.display_name,
          },
        }
      end
    end
  end
end
