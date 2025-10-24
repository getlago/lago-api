# frozen_string_literal: true

require "redlock"
require "redlock/client"

module ActiveJob
  module Uniqueness
    module LockManagerPatch
      extend ActiveSupport::Concern

      DEFAULT_RETRY_OPTIONS = {
        retry_count: 3,
        redis_timeout: 5,
        retry_delay: 200,
        # random delay to avoid lock contention
        retry_jitter: 50,
        exceptions: [Redlock::LockAcquisitionError]
      }

      class << self
        def with_retry(options, &block)
          retry_count = options[:retry_count]
          tries = retry_count + 1
          error = nil

          tries.times do |attempt_number|
            # Wait a random delay before retrying.
            sleep(attempt_retry_delay(attempt_number, options)) if attempt_number > 0

            return yield
          rescue *options[:exceptions] => error
            if attempt_number == tries - 1
              raise error
            end
          end
        end

        private

        def attempt_retry_delay(attempt_number, options)
          retry_delay = options[:retry_delay]
          retry_jitter = options[:retry_jitter]

          retry_delay =
            if retry_delay.respond_to?(:call)
              retry_delay.call(attempt_number)
            else
              retry_delay
            end

          (retry_delay + rand(retry_jitter)).to_f / 1000
        end
      end

      def lock(resource, ttl, options = {}, &block)
        ActiveJob::Uniqueness::LockManagerPatch.with_retry(DEFAULT_RETRY_OPTIONS) do
          super(resource, ttl, options, &block)
        end
      end
    end
  end
end

ActiveJob::Uniqueness::LockManager.include(ActiveJob::Uniqueness::LockManagerPatch)
