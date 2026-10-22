# frozen_string_literal: true

module Contracts
  # Serializes the advance pricing of one contract product. Each event reads the persisted
  # aggregation state and saves the next one, so two events priced at once would both build on
  # the same state and one of them would be lost.
  #
  # A session lock, because the read and the save run in separate transactions.
  class AdvanceStateLockService < BaseLockService
    def initialize(contract:, product:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT)
      @contract = contract
      @product = product

      super(timeout_seconds:, transaction: false)
    end

    private

    attr_reader :contract, :product

    def lock_owner
      Contract
    end

    def lock_key
      "contract-#{contract.id}-product-#{product.id}-advance-state"
    end
  end
end
