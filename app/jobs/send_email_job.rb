# frozen_string_literal: true

class SendEmailJob < ActionMailer::MailDeliveryJob
  queue_as "mailers"

  retry_on ActiveJob::DeserializationError, wait: :exponentially_longer, attempts: 6
  retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 6
end
