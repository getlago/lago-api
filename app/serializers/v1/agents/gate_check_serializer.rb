# frozen_string_literal: true

module V1
  module Agents
    class GateCheckSerializer < ModelSerializer
      def serialize
        {
          allowed: model.allowed,
          reason: model.reason,
          external_subscription_id: model.external_subscription_id,
          wallet_code: model.wallet_code,
          balance_credits: model.balance_credits,
          billing_instructions: model.billing_instructions
        }
      end
    end
  end
end
