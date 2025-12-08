# frozen_string_literal: true

class SendEmailJob < ActionMailer::MailDeliveryJob
  queue_as "mailers"

  retry_on ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 6
  retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 6
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 6
  retry_on Net::SMTPServerBusy, wait: :polynomially_longer, attempts: 25
end
