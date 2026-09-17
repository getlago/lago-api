# frozen_string_literal: true

class PasswordResetMailer < ApplicationMailer
  def requested
    @password_reset = params[:password_reset]
    @email = @password_reset.user.email

    return if @password_reset.token.blank?
    return if @email.blank?

    @reset_url = "#{Rails.application.config.lago_front_url}/reset-password/#{@password_reset.token}"
    @forgot_url = "#{Rails.application.config.lago_front_url}/forgot-password"

    I18n.with_locale(:en) do
      mail(
        to: @email,
        from: ENV["LAGO_FROM_EMAIL"],
        subject: I18n.t("email.password_reset.subject")
      )
    end
  end
end
