# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  module Analytics
    class InvoicedUsageSerializer < ModelSerializer
      def serialize
        {
          month: model["month"],
          code: model["code"],
          currency: model["currency"],
          amount_cents: model["amount_cents"]
        }
      end
    end
  end
end
