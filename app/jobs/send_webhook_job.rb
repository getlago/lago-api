# frozen_string_literal: true

require Rails.root.join('lib/lago_http_client/lago_http_client')

class SendWebhookJob < ApplicationJob
  queue_as 'webhook'

  retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 3

  def perform(webhook_type, object)
    case webhook_type
    when :invoice
      Webhooks::InvoicesService.new(object).call
    else
      raise NotImplementedError
    end
  end
end
