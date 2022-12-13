# frozen_string_literal: true

module V1
  class WalletSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        status: model.status,
        currency: model.currency,
        name: model.name,
        rate_amount: model.rate_amount,
        credits_balance: model.credits_balance,
        balance: model.balance,
        consumed_credits: model.consumed_credits,
        created_at: model.created_at&.iso8601,
        expiration_at: model.expiration_at&.iso8601,
        last_balance_sync_at: model.last_balance_sync_at&.iso8601,
        last_consumed_credit_at: model.last_consumed_credit_at&.iso8601,
        terminated_at: model.terminated_at,
      }.merge(legacy_values)
    end

    def legacy_values
      ::V1::Legacy::WalletSerializer.new(
        model,
      ).serialize
    end
  end
end
