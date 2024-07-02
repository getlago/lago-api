# frozen_string_literal: true

module V1
  module Analytics
    class GrossRevenueSerializer < ModelSerializer
      def serialize
        {
          month: model["month"],
          amount_cents: model["amount_cents"],
          currency: model["currency"],
          invoices_count: model["invoices_count"]
        }
      end
    end
  end
end
