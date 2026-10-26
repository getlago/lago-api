# frozen_string_literal: true

module V2
  module CreditNotes
    class ItemSerializer < ModelSerializer
      def serialize
        {
          lago_fee_id: model.fee_id,
          amount_cents: model.amount_cents
        }
      end
    end
  end
end
