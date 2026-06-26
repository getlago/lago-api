# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  module Analytics
    class InvoiceCollectionSerializer < ModelSerializer
      def serialize
        {
          month: model["month"],
          payment_status: model["payment_status"],
          invoices_count: model["invoices_count"],
          amount_cents: model["amount_cents"],
          currency: model["currency"]
        }
      end
    end
  end
end
