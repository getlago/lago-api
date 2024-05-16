# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  layout 'mailer'

  self.delivery_job = SendEmailJob

  before_action :set_shared_variables

  def set_shared_variables
    @lago_logo_url = "https://assets.getlago.com/lago-logo-email.png"
  end
end
