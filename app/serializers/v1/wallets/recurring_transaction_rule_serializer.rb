# frozen_string_literal: true

module V1
  module Wallets
    class RecurringTransactionRuleSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          rule_type: model.trigger, # NOTE: Legacy field
          paid_credits: model.paid_credits,
          granted_credits: model.granted_credits,
          interval: model.interval,
          threshold_credits: model.threshold_credits,
          trigger: model.trigger,
          created_at: model.created_at.iso8601,
        }
      end
    end
  end
end
