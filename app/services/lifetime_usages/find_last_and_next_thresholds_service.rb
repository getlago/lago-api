# frozen_string_literal: true

module LifetimeUsages
  class FindLastAndNextThresholdsService < BaseService
    def initialize(lifetime_usage:)
      @lifetime_usage = lifetime_usage
      @thresholds = lifetime_usage.subscription.plan.usage_thresholds

      super
    end

    def call
      result.last_threshold_amount_cents = last_threshold_amount_cents
      result.next_threshold_amount_cents = next_threshold_amount_cents
      result.next_treshold_ratio = next_treshold_ratio
      result
    end

    private

    attr_reader :lifetime_usage, :thresholds
    delegate :organization, :subscription, to: :lifetime_usage

    def last_applied_usage_threshold
      return @last_applied_usage_threshold if defined?(@last_applied_usage_threshold)

      subscription_ids = organization.subscriptions
        .where(external_id: subscription.external_id, subscription_at: subscription.subscription_at)
        .where(canceled_at: nil)
        .select(:id)

      @last_applied_usage_threshold = AppliedUsageThreshold
        .joins(invoice: :invoice_subscriptions)
        .where(invoice_subscriptions: {subscription_id: subscription_ids})
        .order(created_at: :desc)
        .first
    end

    def next_usage_threshold
      return @next_usage_threshold if defined?(@next_usage_threshold)

      @next_usage_threshold = thresholds
        .not_recurring
        .where('amount_cents > ?', lifetime_usage.total_amount_cents)
        .order(amount_cents: :asc)
        .first

      @next_usage_threshold ||= thresholds.recurring.first
    end

    def largest_threshold
      @largest_threshold ||= thresholds.not_recurring.order(amount_cents: :desc).first
    end

    def last_threshold_amount_cents
      last_threshold = last_applied_usage_threshold&.usage_threshold
      return unless last_threshold

      if last_threshold.recurring?
        recurring_amount = lifetime_usage.total_amount_cents - (largest_threshold.amount_cents || 0)
        occurence = recurring_amount / last_threshold.amount_cents

        largest_threshold.amount_cents + occurence * last_threshold.amount_cents
      else
        last_threshold.amount_cents
      end
    end

    def next_threshold_amount_cents
      return unless next_usage_threshold
      return next_usage_threshold.amount_cents unless next_usage_threshold.recurring?

      recurring_amount = lifetime_usage.total_amount_cents - (largest_threshold.amount_cents || 0)
      occurence = recurring_amount.fdiv(next_usage_threshold.amount_cents).ceil

      largest_threshold.amount_cents + occurence * next_usage_threshold.amount_cents
    end

    def next_treshold_ratio
      return unless next_usage_threshold

      base_amount_cents = lifetime_usage.total_amount_cents - (last_threshold_amount_cents || 0)
      base_amount_cents.fdiv(next_threshold_amount_cents - (last_threshold_amount_cents || 0))
    end
  end
end
