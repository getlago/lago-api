# frozen_string_literal: true

module V1
  module Legacy
    class CreditSerializer < ModelSerializer
      def serialize
        {
          before_vat: model.before_taxes,
          item: {
            lago_id: model.item_id
          }
        }
      end
    end
  end
end
