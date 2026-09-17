# frozen_string_literal: true

module Admin
  class SlackNotificationJob < ApplicationJob
    queue_as :default

    retry_on Admin::SlackNotificationService::DeliveryError, wait: :polynomially_longer, attempts: 5

    def perform(audit_log_id)
      audit_log = CsAdminAuditLog.find(audit_log_id)
      Admin::SlackNotificationService.call!(audit_log:)
    end
  end
end
