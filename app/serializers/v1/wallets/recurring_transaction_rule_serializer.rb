# frozen_string_literal: true

module V1
  module Wallets
    class RecurringTransactionRuleSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          paid_credits: model.paid_credits,
          granted_credits: model.granted_credits,
          interval: model.interval,
          method: model.method,
          started_at: model.started_at&.iso8601,
          target_ongoing_balance: model.target_ongoing_balance,
          threshold_credits: model.threshold_credits,
          trigger: model.trigger,
          created_at: model.created_at.iso8601,
          invoice_requires_successful_payment: model.invoice_requires_successful_payment?,
          transaction_metadata: model.transaction_metadata
        }
      end
    end
  end
end
