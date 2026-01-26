# frozen_string_literal: true

module WalletTransactions
  class TrackConsumptionService < BaseService
    Result = BaseResult

    def initialize(outbound_wallet_transaction:)
      @outbound_wallet_transaction = outbound_wallet_transaction

      super
    end

    def call
      ActiveRecord::Base.transaction do
        consume_by_priority
      end

      result
    end

    private

    attr_reader :outbound_wallet_transaction

    delegate :wallet, to: :outbound_wallet_transaction

    def consume_by_priority
      amount_cents = outbound_wallet_transaction.amount_cents
      inbounds = available_inbounds.to_a
      available_amount = inbounds.sum(&:remaining_amount_cents)

      if amount_cents > available_amount
        return result.single_validation_failure!(
          field: :amount_cents,
          error_code: "exceeds_available_amount"
        )
      end

      amount_left = amount_cents

      inbounds.each do |inbound|
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

      # this raises a DB error if the remaining_amount_cents goes below zero
      inbound.decrement!(:remaining_amount_cents, amount_cents) # rubocop:disable Rails/SkipsModelValidations
    end

    def available_inbounds
      wallet.wallet_transactions.available_inbound.in_consumption_order
    end
  end
end
