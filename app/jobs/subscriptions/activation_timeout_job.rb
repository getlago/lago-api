# frozen_string_literal: true

module Subscriptions
  class ActivationTimeoutJob < ApplicationJob
    queue_as :default

    def perform(subscription)
      return unless subscription.activating?

      invoice = subscription.invoices.order(created_at: :desc).first
      return unless invoice

      Subscriptions::ActivationFailedService.call!(subscription:, invoice:)
    end
  end
end
