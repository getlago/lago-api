# frozen_string_literal: true

module Admin
  class SlackNotificationService < ::BaseService
    def initialize(audit_log:)
      @audit_log = audit_log
      super
    end

    def call
      webhook_url = ENV.fetch("CS_ADMIN_SLACK_WEBHOOK_URL", nil)
      return result unless webhook_url.present?

      payload = build_payload
      LagoHttpClient::Client.new(webhook_url).post_with_response(payload, {})

      result
    rescue => e
      Rails.logger.error("Slack notification failed for audit log #{audit_log.id}: #{e.message}")
      result
    end

    private

    attr_reader :audit_log

    def build_payload
      emoji = audit_log.toggle_on? || audit_log.org_created? ? "\u2705" : "\u274c"
      action_text = case audit_log.action
      when "toggle_on" then "enabled"
      when "toggle_off" then "disabled"
      when "org_created" then "set on new org"
      when "rollback" then "rolled back"
      end

      {
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "[#{emoji} #{audit_log.feature_key} #{action_text}] on *#{audit_log.organization.name}* by #{audit_log.actor_email} — reason: \"#{audit_log.reason}\""
            }
          }
        ]
      }
    end
  end
end
