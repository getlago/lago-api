# frozen_string_literal: true

module V1
  module Analytics
    class InvoicedUsageSerializer < ModelSerializer
      def serialize
        {
          month: model["month"],
          code: model["code"],
          currency: model["currency"],
          amount_cents: model["amount_cents"]&.to_i
        }
      end
    end
  end
end
