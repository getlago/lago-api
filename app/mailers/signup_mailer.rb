# frozen_string_literal: true

class SignupMailer < ApplicationMailer
  def verification
    @pending_signup = params[:pending_signup]
    return if @pending_signup.email.blank?

    # Issued here, inside the mailer action, so no job argument or mailer param ever holds the token.
    token = Signups::IssueVerificationTokenService.call!(pending_signup: @pending_signup).token
    @verify_url = "#{Rails.application.config.lago_front_url}/verify-email?token=#{token}"

    I18n.with_locale(:en) do
      mail(to: @pending_signup.email, from: ENV["LAGO_FROM_EMAIL"], subject: I18n.t("email.signup.verification.subject"))
    end
  end

  def account_exists
    @pending_signup = params[:pending_signup]
    return if @pending_signup.email.blank?

    @login_url = "#{Rails.application.config.lago_front_url}/login"
    @forgot_url = "#{Rails.application.config.lago_front_url}/forgot-password"

    I18n.with_locale(:en) do
      mail(to: @pending_signup.email, from: ENV["LAGO_FROM_EMAIL"], subject: I18n.t("email.signup.account_exists.subject"))
    end
  end
end
