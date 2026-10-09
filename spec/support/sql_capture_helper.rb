# frozen_string_literal: true

module SqlCaptureHelper
  IGNORED_QUERY_NAMES = %w[SCHEMA TRANSACTION].freeze

  def capture_sql
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] }, "sql.active_record") { yield }
    statements
  end

  # The queries the block runs itself, to compare query counts: schema lookups and transaction
  # statements depend on what the process ran before, and other threads are not the block's.
  # Query cache hits stay: a repeated lookup is what an N+1 on a shared record looks like.
  def capture_counted_queries
    thread = Thread.current
    statements = []
    callback = lambda do |*, payload|
      next if IGNORED_QUERY_NAMES.include?(payload[:name]) || !Thread.current.equal?(thread)

      statements << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end
end
