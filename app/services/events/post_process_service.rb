# frozen_string_literal: true

module Events
  class PostProcessService < BaseService
    def initialize(event:)
      @organization = event.organization
      @event = event
      super
    end

    def call
      event.customer_id = customer&.id
      event.external_customer_id ||= customer&.external_id

      # NOTE: prevent subscription if more than 1 subscription is active
      #       if multiple terminated matches the timestamp, takes the most recent
      if subscriptions.count(&:active?) <= 1
        subscription = subscriptions.first
        event.subscription_id = subscription&.id
        event.external_subscription_id ||= subscription&.external_id
      end

      event.save!

      expire_cached_charges(subscriptions)

      if should_handle_quantified_event?
        # For unique count if repeated event got ingested, we want to store this event but prevent further processing
        return result unless quantified_event_service.process_event?

        handle_quantified_event
      end

      handle_pay_in_advance

      result.event = event
      result
    rescue ActiveRecord::RecordInvalid => e
      delivor_error_webhook(error: e.record.errors.messages)

      result
    rescue ActiveRecord::RecordNotUnique
      delivor_error_webhook(error: { transaction_id: ['value_already_exist'] })

      result
    end

    private

    attr_reader :event

    delegate :organization, to: :event

    def customer
      return @customer if defined? @customer

      @customer = if event.external_subscription_id
        organization.subscriptions.find_by(external_id: event.external_subscription_id)&.customer
      else
        Customer.find_by(external_id: event.external_customer_id, organization_id: organization.id)
      end
    end

    def subscriptions
      return @subscriptions if defined? @subscriptions

      subscriptions = if customer && event.external_subscription_id.blank?
        customer.subscriptions
      else
        organization.subscriptions.where(external_id: event.external_subscription_id)
      end
      return unless subscriptions

      @subscriptions = subscriptions
        .where("date_trunc('second', started_at::timestamp) <= ?::timestamp", event.timestamp)
        .where(
          "terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?",
          event.timestamp,
        )
        .order('terminated_at DESC NULLS FIRST, started_at DESC')
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
        .where(plans: { id: active_subscription.map(&:plan_id) })

      charges.each do |charge|
        active_subscription.each do |subscription|
          Subscriptions::ChargeCacheService.new(subscription:, charge:).expire_cache
        end
      end
    end

    def quantified_event_service
      @quantified_event_service ||= QuantifiedEvents::CreateOrUpdateService.new(event)
    end

    def should_handle_quantified_event?
      quantified_event_service.matching_billable_metric?
    end

    def handle_quantified_event
      service_result = quantified_event_service.call
      service_result.raise_if_error!

      # TODO: Remove this relation
      event.quantified_event_id = service_result.quantified_event&.id
      event.save!
    end

    def handle_pay_in_advance
      return unless billable_metric

      charges.where(invoiceable: false).find_each do |charge|
        Fees::CreatePayInAdvanceJob.perform_later(charge:, event:)
      end

      # NOTE: ensure event is processable
      return if !billable_metric.count_agg? && event.properties[billable_metric.field_name].nil?

      charges.where(invoiceable: true).find_each do |charge|
        Invoices::CreatePayInAdvanceChargeJob.perform_later(charge:, event:, timestamp: event.timestamp)
      end
    end

    def charges
      return Charge.none unless subscriptions.first

      subscriptions
        .first
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: { code: event.code })
    end

    def delivor_error_webhook(error:)
      return unless organization.webhook_endpoints.any?

      SendWebhookJob.perform_later('event.error', event, { error: })
    end
  end
end
