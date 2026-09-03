# frozen_string_literal: true

module Admin
  class SlackNotificationService < ::BaseService
    def initialize(audit_log:)
      @audit_log = audit_log
      super()
    end

    def call
      webhook_url = ENV.fetch("CS_ADMIN_SLACK_WEBHOOK_URL", nil)
      return result if webhook_url.blank?

      payload = build_payload
      LagoHttpClient::Client.new(webhook_url).post_with_response(payload, {})

      result
    rescue LagoHttpClient::HttpError => e
      Rails.logger.error("Slack notification failed for audit log #{audit_log.id}: HTTP #{e.error_code} - #{e.error_body}")
      result
    rescue => e
      Rails.logger.error("Slack notification failed for audit log #{audit_log.id}: #{e.class}")
      result
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
