# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  module Analytics
    class MrrSerializer < ModelSerializer
      def serialize
        {
          month: model["month"],
          amount_cents: model["amount_cents"],
          currency: model["currency"]
        }
      end
    end
  end
end
