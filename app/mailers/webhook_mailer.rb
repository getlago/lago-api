# frozen_string_literal: true

class WebhookMailer < ApplicationMailer
  def failure_notification
    @webhook = params[:webhook]
    @org_name = @webhook.organization.name
    @front_webhooks_url = "#{ENV["LAGO_FRONT_URL"]}/developers/webhooks"
    @failed_webhooks_count = @webhook.organization.webhooks.failed.where(last_retried_at: 1.hour.ago..).count

    @emails = @webhook.organization.admins.pluck(:email)
    if @webhook.organization.email
      @emails += @webhook.organization.email.split(",")
    end

    I18n.with_locale(:en) do
      mail(
        to: @emails,
        from: ENV["LAGO_FROM_EMAIL"],
        subject: I18n.t("email.webhook.failure_notification.subject", org_name: @org_name)
      )
    end
  end
end
