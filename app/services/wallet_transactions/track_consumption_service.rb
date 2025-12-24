# frozen_string_literal: true

module WalletTransactions
  class TrackConsumptionService < BaseService
    Result = BaseResult

    def initialize(outbound_wallet_transaction:, inbound_wallet_transaction_id: nil)
      @outbound_wallet_transaction = outbound_wallet_transaction
      @inbound_wallet_transaction_id = inbound_wallet_transaction_id

      super
    end

    def call
      ActiveRecord::Base.transaction do
        if inbound_wallet_transaction_id.present?
          consume_from_specific_inbound
        else
          consume_by_priority
        end
      end

      result
    end

    private

    attr_reader :outbound_wallet_transaction, :inbound_wallet_transaction_id

    delegate :wallet, to: :outbound_wallet_transaction

    def consume_from_specific_inbound
      inbound = wallet.wallet_transactions.inbound.find(inbound_wallet_transaction_id)
      amount_cents = outbound_wallet_transaction.amount_cents

      if amount_cents > inbound.remaining_amount_cents
        return result.single_validation_failure!(
          field: :amount_cents,
          error_code: "exceeds_available_amount"
        )
      end

      create_consumption(inbound, amount_cents)
    end

    def consume_by_priority
      amount_cents = outbound_wallet_transaction.amount_cents
      available_amount = available_inbounds.sum(:remaining_amount_cents) || 0

      if amount_cents > available_amount
        return result.single_validation_failure!(
          field: :amount_cents,
          error_code: "exceeds_available_amount"
        )
      end

      amount_left = amount_cents

      available_inbounds.each do |inbound|
        break if amount_left <= 0

        consume_amount = [inbound.remaining_amount_cents, amount_left].min

        create_consumption(inbound, consume_amount)
        amount_left -= consume_amount
      end
    end

    def create_consumption(inbound, amount_cents)
      WalletTransactionConsumption.create!(
        organization: wallet.organization,
        inbound_wallet_transaction: inbound,
        outbound_wallet_transaction: outbound_wallet_transaction,
        consumed_amount_cents: amount_cents
      )

      inbound.decrement!(:remaining_amount_cents, amount_cents)
    end

    def available_inbounds
      wallet.wallet_transactions
        .inbound
        .settled
        .where("remaining_amount_cents > 0")
        .order(
          Arel.sql("CASE WHEN transaction_status = 1 THEN 0 ELSE 1 END"),
          :priority,
          created_at: :asc
        )
    end
  end
end
