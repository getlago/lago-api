# frozen_string_literal: true

class SendHttpWebhookJob < ApplicationJob
  def perform(webhook)
    Webhooks::SendHttpService.call(webhook:)
  end
end
