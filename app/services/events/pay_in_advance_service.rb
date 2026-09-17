# frozen_string_literal: true

module Events
  class PayInAdvanceService < BaseService
    Result = BaseResult[:event]

    def initialize(event:)
      @event = Events::CommonFactory.new_instance(source: event)
      super
    end

    def call
      return result unless billable_metric
      return result unless can_create_fee?
      return result if already_processed?

      # NOTE: Temporary condition to support both Postgres and Clickhouse (via kafka)
      if kafka_producer_enabled?
        # NOTE: when clickhouse, ignore event coming from postgres (Rest API)
        return result if event.id.present? && event.organization.clickhouse_events_store?

        # NOTE: without clickhouse, ignore events coming from kafka
        return result if event.id.nil? && !event.organization.clickhouse_events_store?
      end

      metered_item_selections.each do |selection|
        enqueue_pay_in_advance_job(selection)
      end

      result.event = event
      result
    end

    private

    attr_reader :event

    delegate :billable_metric, :properties, to: :event

    def metered_item_selections
      @metered_item_selections ||= Events::PayInAdvanceMeteredItemsResolver.call!(event:).selections
    end

    def already_processed?
      Fee.from_organization_pay_in_advance(event.organization).where(pay_in_advance_event_transaction_id: event.transaction_id).exists?
    end

    def can_create_fee?
      # NOTE: `custom_agg` and `count_agg` are the only 2 aggregations
      #       that don't require a field set in property.
      #       For other aggregation, if the field isn't set we shouldn't create a fee/invoice.
      billable_metric.count_agg? || billable_metric.custom_agg? || properties[billable_metric.field_name].present?
    end

    def enqueue_pay_in_advance_job(selection)
      metered_item = selection.metered_item

      if metered_item.invoiceable?
        Invoices::CreatePayInAdvanceChargeJob.perform_later(metered_item:, timestamp: event.timestamp)
      else
        Fees::CreatePayInAdvanceJob.perform_later(metered_item:)
      end
    end

    def kafka_producer_enabled?
      ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].present? && ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"].present?
    end
  end
end
