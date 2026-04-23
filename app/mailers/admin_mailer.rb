# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  def feature_toggled(audit_log:, actor_email:)
    @audit_log = audit_log
    @organization = audit_log.organization
    @actor_email = actor_email
    @feature_key = audit_log.feature_key
    @action = audit_log.toggle_on? ? "enabled" : "disabled"

    owner = @organization.admins.first
    return unless owner&.email.present?

    mail(
      to: owner.email,
      subject: "Feature #{@feature_key} has been #{@action} on your organization"
    )
  end
end
