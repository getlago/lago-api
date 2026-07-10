# frozen_string_literal: true

module Quotes
  # Acquires a PostgreSQL advisory lock scoped to a quote to serialize mutations across the
  # whole quote aggregate (quote, quote versions, order forms and orders).
  #
  # The lock is reentrant: cascade calls that re-enter the same quote lock (e.g. approve ->
  # create order form, expire/void -> void version, clone -> void version) yield immediately
  # within the already-held transaction instead of re-acquiring.
  #
  class LockService < BaseLockService
    def initialize(quote:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
      @quote = quote

      super(timeout_seconds:, transaction:)
    end

    private

    attr_reader :quote

    def lock_owner
      Quote
    end

    def lock_key
      "quote-#{quote.id}"
    end
  end
end
