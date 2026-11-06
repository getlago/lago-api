# frozen_string_literal: true

module Clock
  module ApiKeys
    # The agent destroys its key when a turn ends. This removes the keys a crashed turn left behind.
    class CleanupMemberKeysJob < ClockJob
      unique :until_executed, on_conflict: :log

      def perform
        ApiKey.unscoped.where.not(membership_id: nil).where(expires_at: ...1.day.ago).delete_all
      end
    end
  end
end
