# frozen_string_literal: true

module Events
  class PostProcessService < BaseService
    Result = BaseResult[:event]

    def initialize(event:)
      @organization = event.organization
      @event = event
      super
    end

    def call
      expire_cached_charges(subscriptions)
      track_subscription_activity
      customer&.flag_wallets_for_refresh

      handle_pay_in_advance

      result.event = event
      result
    rescue ActiveRecord::RecordNotUnique
      deliver_error_webhook(error: {transaction_id: ["value_already_exist"]})

      result
    end

    private

    attr_reader :event

    delegate :organization, to: :event

    def customer
      @customer ||= subscriptions.first&.customer
    end

    def subscriptions
      return @subscriptions if defined? @subscriptions

      subscriptions = organization.subscriptions.where(external_id: event.external_subscription_id)
      return unless subscriptions

      @subscriptions = subscriptions
        .where("date_trunc('millisecond', started_at::timestamp) <= ?::timestamp", event.timestamp)
        .where(
          "terminated_at IS NULL OR date_trunc('millisecond', terminated_at::timestamp) >= ?",
          event.timestamp
        )
        .order("terminated_at DESC NULLS FIRST, started_at DESC")
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: event.code)
    end

    def expire_cached_charges(subscriptions)
      active_subscription = subscriptions.select(&:active?)
      return if active_subscription.blank?
      return unless billable_metric

      charges = billable_metric.charges
        .joins(:plan)
        .where(plans: {id: active_subscription.map(&:plan_id)})
        .includes(filters: {values: :billable_metric_filter})

      charges.each do |charge|
        charge_filter = ChargeFilters::EventMatchingService.call(charge:, event:).charge_filter

        active_subscription.each do |subscription|
          Subscriptions::ChargeCacheService.expire_cache(subscription:, charge:, charge_filter:)
        end
      end
    end

    def track_subscription_activity
      # NOTE: We don't eager load usage_thresholds or alerts here so it could be considered an N+1 query
      #       But there should be only one active subscription here, so it's better to not re-requery to eager load
      subscriptions.select(&:active?).each do |subscription|
        UsageMonitoring::TrackSubscriptionActivityService.call(organization:, subscription:)
      end
    end

    def handle_pay_in_advance
      return unless billable_metric
      return unless charges.any?

      Events::PayInAdvanceJob.perform_later(Events::CommonFactory.new_instance(source: event).as_json)
    end

    def charges
      return Charge.none unless subscriptions.first

      subscriptions
        .first
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: {code: event.code})
    end

    def deliver_error_webhook(error:)
      SendWebhookJob.perform_later("event.error", event, {error:})
    end
  end
end
