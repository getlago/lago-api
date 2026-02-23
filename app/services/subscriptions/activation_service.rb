# frozen_string_literal: true

module Subscriptions
  class ActivationService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, invoice:)
      @subscription = subscription
      @invoice = invoice

      super
    end

    def call
      return result unless subscription.activating?

      ActiveRecord::Base.transaction do
        subscription.active!

        finalize_invoice

        if previous_subscription.present?
          Subscriptions::TerminateService.call(
            subscription: previous_subscription,
            upgrade: true
          )
        end
      end

      after_commit do
        SendWebhookJob.perform_later("subscription.started", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.started")

        # Invoice side effects deferred from SubscriptionService
        SendWebhookJob.perform_later("invoice.created", invoice)
        Utils::ActivityLog.produce(invoice, "invoice.created")
        Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_finalized_email?)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
        Utils::SegmentTrack.invoice_created(invoice)
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription, :invoice

    def finalize_invoice
      invoice.issuing_date = Time.current.in_time_zone(subscription.customer.applicable_timezone).to_date
      invoice.payment_due_date = invoice.issuing_date + invoice.net_payment_term.days
      Invoices::FinalizeService.call!(invoice:)
    end

    def previous_subscription
      @previous_subscription ||= subscription.previous_subscription
    end

    def should_deliver_finalized_email?
      License.premium? && subscription.customer.billing_entity.email_settings.include?("invoice.finalized")
    end
  end
end
