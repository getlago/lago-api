# frozen_string_literal: true

module Admin
  module PremiumIntegrations
    class NotifySlackJob < ApplicationJob
      queue_as "default"

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform(organization_id:, organization_name:, integration:, enabled:, reason:, reason_category:, actor_email:, staff_role:, previous_integrations:, current_integrations:)
        webhook_url = ENV["LAGO_STAFF_SLACK_WEBHOOK"]
        return if webhook_url.blank?

        client = LagoHttpClient::Client.new(webhook_url)
        client.post(build_payload(
          organization_id:,
          organization_name:,
          integration:,
          enabled:,
          reason:,
          reason_category:,
          actor_email:,
          staff_role:,
          previous_integrations:,
          current_integrations:
        ), [])
      end

      private

      def build_payload(organization_id:, organization_name:, integration:, enabled:, reason:, reason_category:, actor_email:, staff_role:, previous_integrations:, current_integrations:)
        icon = enabled ? ":white_check_mark:" : ":no_entry:"
        verb = enabled ? "enabled" : "disabled"

        {
          text: "#{icon} Premium integration *#{integration}* #{verb} for *#{organization_name}*",
          blocks: [
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: "#{icon} *#{actor_email || "unknown"}* (#{staff_role}) #{verb} *`#{integration}`* for *#{organization_name}* (`#{organization_id}`)"
              }
            },
            {
              type: "section",
              fields: [
                {type: "mrkdwn", text: "*Reason category*\n#{reason_category}"},
                {type: "mrkdwn", text: "*Reason*\n#{reason}"}
              ]
            },
            {
              type: "context",
              elements: [
                {
                  type: "mrkdwn",
                  text: "Previous: `#{previous_integrations.join(", ")}` → Current: `#{current_integrations.join(", ")}`"
                }
              ]
            }
          ]
        }
      end
    end
  end
end
