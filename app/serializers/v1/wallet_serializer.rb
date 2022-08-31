# frozen_string_literal: true

module V1
  class WalletSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        status: model.status,
        currency: model.currency,
        name: model.name,
        rate_amount: model.rate_amount,
        credits_balance: model.credits_balance,
        balance: model.balance,
        consumed_credits: model.consumed_credits,
        created_at: model.created_at&.iso8601,
        expiration_date: model.expiration_date&.iso8601,
        last_balance_sync_at: model.last_balance_sync_at&.iso8601,
        last_consumed_credit_at: model.last_consumed_credit_at&.iso8601,
        terminated_at: model.terminated_at
      }
    end
  end
end
