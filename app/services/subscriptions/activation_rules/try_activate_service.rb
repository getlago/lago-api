# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class TryActivateService < BaseService
      def initialize(subscription:, invoice:)
        @subscription = subscription
        @invoice = invoice

        super
      end

      def call
        return result if subscription.activation_rules.pending.any?

        Invoices::FinalizeService.call!(invoice:)

        SendWebhookJob.perform_later("invoice.created", invoice)
        Invoices::GenerateDocumentsJob.perform_later(invoice:)
        Utils::ActivityLog.produce(invoice, "invoice.created")

        subscription.mark_as_active!

        SendWebhookJob.perform_later("subscription.started", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.started")

        result
      end

      private

      attr_reader :subscription, :invoice
    end
  end
end
