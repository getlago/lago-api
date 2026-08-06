# frozen_string_literal: true

module Admin
  class EmailNotificationJob < ApplicationJob
    queue_as :mailers

    def perform(audit_log_id, actor_email)
      audit_log = CsAdminAuditLog.find(audit_log_id)
      AdminMailer.feature_toggled(audit_log:, actor_email:).deliver_now
    end
  end
end
