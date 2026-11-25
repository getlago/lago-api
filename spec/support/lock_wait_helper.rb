# frozen_string_literal: true

module LockWaitHelper
  # Sessions of the test database waiting on a row or table lock, for race specs that wait until a thread is blocked
  def lock_waits
    ApplicationRecord.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    )
  end
end
