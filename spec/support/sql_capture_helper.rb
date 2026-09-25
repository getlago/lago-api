# frozen_string_literal: true

module SqlCaptureHelper
  def capture_sql
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] }, "sql.active_record") { yield }
    statements
  end
end
