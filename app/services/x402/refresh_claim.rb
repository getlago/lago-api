# frozen_string_literal: true

module X402
  class RefreshClaim
    TTL = 5.minutes

    def self.acquire(customer)
      new(customer).acquire
    end

    def initialize(customer)
      @customer = customer
      @token = SecureRandom.uuid
    end

    def acquire
      claimed = ReservationCounter.redis.then { |client| client.set(key, token, nx: true, px: TTL.in_milliseconds) }

      if claimed
        self
      end
    rescue *ReservationCounter::UNAVAILABLE_ERRORS => e
      report(e)
      nil
    end

    def release(reservations)
      ReservationCounter.redis.then do |client|
        client.watch(key) do
          if client.get(key) == token
            client.multi do |transaction|
              reservations.each do |wallet, cents|
                counter = ReservationCounter.key(wallet)
                transaction.decrby(counter, cents)
                transaction.expire(counter, ReservationCounter::TTL.to_i, nx: true)
              end
              transaction.del(key)
            end
          else
            client.unwatch
          end
        end
      end
    rescue *ReservationCounter::UNAVAILABLE_ERRORS => e
      report(e)
      nil
    end

    def drop
      release({})
    end

    private

    attr_reader :customer, :token

    def key
      "x402:refreshing:#{customer.id}"
    end

    def report(error)
      Rails.logger.warn("[x402] refresh claim unavailable customer_id=#{customer.id}: #{error.class} #{error.message}")
      Sentry.capture_exception(error, extra: {organization_id: customer.organization_id, customer_id: customer.id})
    end
  end
end
