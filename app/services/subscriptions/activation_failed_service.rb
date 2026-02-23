# frozen_string_literal: true

module Subscriptions
  class ActivationFailedService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, invoice:)
      @subscription = subscription
      @invoice = invoice

      super
    end

    def call
      return result unless subscription.activating?

      ActiveRecord::Base.transaction do
        subscription.clear_activation!
        subscription.terminated_at = Time.current
        subscription.terminated!

        invoice.status = :closed
        invoice.save!
      end

      after_commit do
        Subscriptions::Payments::CancelService.call(invoice:)
        SendWebhookJob.perform_later("subscription.activation_failed", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.activation_failed")
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription, :invoice
  end
end
