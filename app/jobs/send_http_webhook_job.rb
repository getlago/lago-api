# frozen_string_literal: true

class SendHttpWebhookJob < ApplicationJob
  queue_as do
    if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_WEBHOOK"])
      :webhook_worker
    else
      :webhook
    end
  end

  def perform(webhook)
    Webhooks::SendHttpService.call(webhook:)
  end
end
