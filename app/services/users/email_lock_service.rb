# frozen_string_literal: true

module Users
  # Serializes signup email and user creation for one mailbox: users.email has no unique index, so every path that
  # creates a user while self-serve is on takes this lock.
  class EmailLockService < BaseService
    Result = BaseResult[:value]

    RETRY_DELAY = (0.05..0.15)

    def initialize(email:, timeout_seconds: BaseLockService::ACQUIRE_LOCK_TIMEOUT)
      @email = email
      @timeout_seconds = timeout_seconds
      super
    end

    def call
      result.value = ApplicationRecord.transaction do
        acquire!
        yield
      end

      result
    end

    private

    attr_reader :email, :timeout_seconds

    # A 64-bit transaction lock: with_advisory_lock's 31-bit CRC32 keys let an attacker pick an address sharing a
    # victim's lock, and it writes the name into a SQL comment. The error never names the address.
    def acquire!
      key = Digest::SHA256.digest("user-email:#{Signups::ValidateEmailService.mailbox_key(email)}").unpack1("q>")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      # The executor caches reads for the whole request or job: each poll must reach the database, and a check
      # repeated under the lock must not read the answer cached before it.
      ApplicationRecord.uncached do
        until locked?(key)
          raise BaseLockService::FailedToAcquireLock, "Failed to acquire the email lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep(rand(RETRY_DELAY))
        end
      end
      ApplicationRecord.connection_pool.clear_query_cache
    end

    def locked?(key)
      ApplicationRecord.connection.select_value(ApplicationRecord.sanitize_sql_array(["SELECT pg_try_advisory_xact_lock(?)", key]))
    end
  end
end
