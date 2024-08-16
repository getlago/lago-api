# frozen_string_literal: true

module LifetimeUsages
  class FlagRefreshFromInvoiceService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result unless invoice.subscription?
      return result unless invoice.finalized? || invoice.voided?
      return result unless has_plan_usage_thresholds?

      result.lifetime_usages = []

      invoice.subscriptions.each do |subscription|
        lifetime_usage = subscription.lifetime_usage
        lifetime_usage ||= subscription.build_lifetime_usage(organization: subscription.organization)
        lifetime_usage.recalculate_invoiced_usage = true
        lifetime_usage.save!

        result.lifetime_usages << lifetime_usage
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice

    def has_plan_usage_thresholds?
      invoice.subscriptions.any? { |s| s.plan.usage_thresholds.any? }
    end
  end
end
