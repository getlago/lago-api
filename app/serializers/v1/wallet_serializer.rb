# frozen_string_literal: true

module V1
  class WalletSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        status: model.status,
        currency: model.currency,
        name: model.name,
        rate_amount: model.rate_amount,
        credits_balance: model.credits_balance,
        credits_ongoing_balance: model.credits_ongoing_balance,
        credits_ongoing_usage_balance: model.credits_ongoing_usage_balance,
        balance_cents: model.balance_cents,
        ongoing_balance_cents: model.ongoing_balance_cents,
        ongoing_usage_balance_cents: model.ongoing_usage_balance_cents,
        consumed_credits: model.consumed_credits,
        created_at: model.created_at&.iso8601,
        expiration_at: model.expiration_at&.iso8601,
        last_balance_sync_at: model.last_balance_sync_at&.iso8601,
        last_consumed_credit_at: model.last_consumed_credit_at&.iso8601,
        terminated_at: model.terminated_at
      }

      payload.merge!(recurring_transaction_rules) if include?(:recurring_transaction_rules)

      payload
    end

    private

    def recurring_transaction_rules
      ::CollectionSerializer.new(
        model.recurring_transaction_rules,
        ::V1::Wallets::RecurringTransactionRuleSerializer,
        collection_name: 'recurring_transaction_rules'
      ).serialize
    end
  end
end
