# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  self.delivery_job = SendEmailJob
end
