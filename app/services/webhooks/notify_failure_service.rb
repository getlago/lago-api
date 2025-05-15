# frozen_string_literal: true

module Webhooks
  class NotifyFailureService < ::BaseService
    def initialize(webhook:)
      @webhook = webhook
      super
    end

    def call
      return result unless should_notify?

      WebhookMailer.with(webhook:).failure_notification.deliver_later

      # Store the last notification time
      Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)

      result
    end

    private

    attr_reader :webhook

    def should_notify?
      # NOTE: Only notify if we haven't sent an email in the last hour,
      #       to avoid hundreds of emails going out when the endpoint is down
      last_notification = Rails.cache.read(cache_key)
      return true if last_notification.nil?

      Time.current - last_notification >= 1.hour
    end

    def cache_key
      "webhook_failure_notification:#{webhook.organization_id}"
    end
  end
end
