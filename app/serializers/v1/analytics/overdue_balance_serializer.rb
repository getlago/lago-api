# frozen_string_literal: true

module V1
  module Analytics
    class OverdueBalanceSerializer < ModelSerializer
      def serialize
        {
          month: model["month"],
          amount_cents: model["amount_cents"],
          currency: model["currency"],
          invoice_ids: JSON.parse(model["invoice_ids"])
        }
      end
    end
  end
end
