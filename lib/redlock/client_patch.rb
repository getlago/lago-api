# frozen_string_literal: true

require "redlock"
require "redlock/client"

# Redlock retry logic actually behaves the same whether there's an error (network, Redis error, etc.) or whether it
# fails to lock because the resource is already locked. So, if we enable redlock retry, whenever we try to enqueue a job
# for which there's already a job locked (enqueued or running), we’ll try 3 times to enqueue the job causing a ~0.5s
# delay.
#
# This patch is used to work around this issue by retrying the lock acquisition only if there is a network error.
module Redlock
  module ClientPatch
    def lock(resource, ttl, options = {}, &block)
      with_retry_on_error do
        super(resource, ttl, options, &block)
      end
    end

    private

    def with_retry_on_error(&block)
      tries = Redlock::Client::DEFAULT_RETRY_COUNT + 1
      error = nil
      tries.times do |attempt_number|
        # Wait a random delay before retrying.
        attempt_retry_delay = (Redlock::Client::DEFAULT_RETRY_DELAY + rand(Redlock::Client::DEFAULT_RETRY_JITTER)).to_f / 1000
        sleep(attempt_retry_delay) if attempt_number > 0

        return yield
      rescue Redlock::LockAcquisitionError => error
        if attempt_number == tries - 1
          raise error
        end
      end
    end
  end
end

Redlock::Client.prepend(Redlock::ClientPatch)
