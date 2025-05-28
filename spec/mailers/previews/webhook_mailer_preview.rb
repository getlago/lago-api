# frozen_string_literal: true

class WebhookMailerPreview < BasePreviewMailer
  def failure_notification
    organization = FactoryBot.create(:organization, name: "App Staging")
    webhooks = FactoryBot.create_list(:webhook, 3, :failed_with_retries, organization:)
    WebhookMailer.with(webhook: webhooks.last).failure_notification
  end
end
