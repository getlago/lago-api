# frozen_string_literal: true

module Invoices
  class RateSchedulesBillingService < BaseService
    Result = BaseResult[:invoice]

    def initialize(subscription_rate_schedules:, timestamp:, invoice: nil)
      @subscription_rate_schedules = subscription_rate_schedules
      @timestamp = timestamp
      @invoice = invoice
      @customer = subscription_rate_schedules.first.subscription.customer
      @currency = subscription_rate_schedules.first.rate_schedule.amount_currency

      super
    end

    def call
      if invoice&.generating?
        result.invoice = invoice
      else
        ActiveRecord::Base.transaction do
          create_generating_invoice
          result.invoice = invoice

          create_invoice_subscriptions

          RateSchedules::CalculateFeesService.call!(
            invoice:,
            subscription_rate_schedules:
          )

          invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
          invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
          invoice.save!
        end
      end

      set_invoice_status
      invoice.save!

      enqueue_post_processing_jobs

      result
    end

    private

    attr_reader :subscription_rate_schedules, :timestamp, :customer, :currency

    attr_accessor :invoice

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        invoicing_reason: :subscription_periodic,
        currency:,
        datetime: Time.zone.at(timestamp)
      )
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def create_invoice_subscriptions
      subscription_rate_schedules.group_by(&:subscription_id).each_value do |srs_group|
        subscription = srs_group.first.subscription

        InvoiceSubscription.create!(
          organization: subscription.organization,
          invoice:,
          subscription:,
          timestamp: Time.zone.at(timestamp),
          recurring: true,
          invoicing_reason: :subscription_periodic
        )
      end
    end

    def set_invoice_status
      if grace_period?
        invoice.status = :draft
      else
        Invoices::TransitionToFinalStatusService.call(invoice:)
      end
    end

    def grace_period?
      @grace_period ||= customer.applicable_invoice_grace_period.positive?
    end

    def enqueue_post_processing_jobs
      if grace_period?
        SendWebhookJob.perform_after_commit("invoice.drafted", invoice)
        Utils::ActivityLog.produce_after_commit(invoice, "invoice.drafted")
      else
        return if invoice.closed?

        SendWebhookJob.perform_after_commit("invoice.created", invoice)
        Utils::ActivityLog.produce_after_commit(invoice, "invoice.created")
        GenerateDocumentsJob.perform_after_commit(invoice:, notify: should_deliver_finalized_email?)
        Integrations::Aggregator::Invoices::CreateJob.perform_after_commit(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_after_commit(invoice:) if invoice.should_sync_hubspot_invoice?
        Invoices::Payments::CreateService.call_async(invoice:)
        Utils::SegmentTrack.invoice_created(invoice)
      end
    end

    def should_deliver_finalized_email?
      customer.organization.email_settings.include?("invoice.finalized")
    end
  end
end
