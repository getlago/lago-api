# frozen_string_literal: true

module V1
  module X402
    class GateCheckSerializer < ModelSerializer
      def serialize
        {
          balance_credits: model.balance_credits,
          requirements: model.requirements,
          external_subscription_id: model.external_subscription_id,
          subscription_started_at: model.subscription_started_at&.iso8601(3),
          sign_in_chains: model.sign_in_chains
        }
      end
    end
  end
end
