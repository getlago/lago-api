# frozen_string_literal: true

module Admin
  class SlackNotificationService < ::BaseService
    Result = BaseResult

    class DeliveryError < StandardError; end

    def initialize(audit_log:)
      @audit_log = audit_log
      super()
    end

    def call
      webhook_url = ENV.fetch("CS_ADMIN_SLACK_WEBHOOK_URL", nil)
      return result if webhook_url.blank?

      payload = build_payload
      LagoHttpClient::Client.new(webhook_url, open_timeout: 5, read_timeout: 10, write_timeout: 10)
        .post_with_response(payload, {})

      result
    rescue LagoHttpClient::HttpError => e
      message = "Slack notification failed for audit log #{audit_log.id}: HTTP #{e.error_code}"
      if e.error_code.to_i == 429 || e.error_code.to_i >= 500
        raise DeliveryError, message, cause: nil
      end

      result.service_failure!(code: "slack_notification_failed", message:)
    rescue *LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES => e
      raise DeliveryError, "Slack notification failed for audit log #{audit_log.id}: #{e.class}", cause: nil
    end

    private

    attr_reader :audit_log

    def build_payload
      {
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: message_text
            }
          }
        ]
      }
    end

    def message_text
      if audit_log.feature_type == "organization"
        "[#{emoji} Organization created] *#{escape_mrkdwn(audit_log.organization.name)}* by #{escape_mrkdwn(audit_log.actor_email)} — reason: \"#{escape_mrkdwn(audit_log.reason)}\""
      else
        "[#{emoji} #{escape_mrkdwn(audit_log.feature_key)} #{action_text}] on *#{escape_mrkdwn(audit_log.organization.name)}* by #{escape_mrkdwn(audit_log.actor_email)} — reason: \"#{escape_mrkdwn(audit_log.reason)}\""
      end
    end

    def escape_mrkdwn(value)
      value.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub(/\s+/, " ")
    end

    def emoji
      if audit_log.toggle_on? || audit_log.org_created?
        "✅"
      else
        "❌"
      end
    end

    def action_text
      case audit_log.action
      when "toggle_on" then "enabled"
      when "toggle_off" then "disabled"
      when "org_created" then "set on new org"
      when "rollback" then "rolled back"
      end
    end
  end
end
