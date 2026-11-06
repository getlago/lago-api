# frozen_string_literal: true

module Contracts
  # Serializes the advance pricing of one contract product filter. Each event reads the persisted
  # aggregation state and saves the next one, so two events priced at once would both build on
  # the same state and one of them would be lost.
  #
  # Keyed like that state: the default card and each filtered card of a product keep their own,
  # and the card versions of one filter share it.
  #
  # A session lock, because the read and the save run in separate transactions.
  class AdvanceStateLockService < BaseLockService
    def initialize(contract:, product:, product_filter:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT)
      @contract = contract
      @product = product
      @product_filter = product_filter

      super(timeout_seconds:, transaction: false)
    end

    private

    attr_reader :contract, :product, :product_filter

    def lock_owner
      Contract
    end

    def lock_key
      "contract-#{contract.id}-product-#{product.id}-filter-#{product_filter&.id || "default"}-advance-state"
    end
  end
end
