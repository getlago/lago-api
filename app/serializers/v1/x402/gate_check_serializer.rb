# frozen_string_literal: true

module V1
  module X402
    class GateCheckSerializer < ModelSerializer
      def serialize
        {
          balance_credits: model.balance_credits,
          requirements: model.requirements,
          external_subscription_id: model.external_subscription_id
        }
      end
    end
  end
end
