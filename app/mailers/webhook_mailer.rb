# frozen_string_literal: true

class WebhookMailer < ApplicationMailer
  def failure_notification
    @webhook = params[:webhook]
    @organization = @webhook.organization
    @front_webhooks_url = "#{ENV["LAGO_FRONT_URL"]}/developers/webhooks"
    @failed_webhooks_count = @webhook.organization.webhooks.failed.where(last_retried_at: 1.hour.ago..).count

    @emails = @organization.admins.pluck(:email)
    if @organization.email
      @emails += @organization.email.split(",")
    end

    mail(
      to: @emails,
      from: ENV["LAGO_FROM_EMAIL"],
      subject: "[ALERT] Webhook delivery failed for #{@organization.name}"
    )
  end
end
