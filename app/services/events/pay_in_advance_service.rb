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
      return result if all_already_processed?

      # NOTE: Temporary condition to support both Postgres and Clickhouse (via kafka)
      if kafka_producer_enabled?
        # NOTE: when clickhouse, ignore event coming from postgres (Rest API)
        return result if event.id.present? && event.organization.clickhouse_events_store?

        # NOTE: without clickhouse, ignore events coming from kafka
        return result if event.id.nil? && !event.organization.clickhouse_events_store?
      end

      metered_item_selections.each do |selection|
        next if already_processed?(selection.metered_item)

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

    def all_already_processed?
      return already_processed? unless event.organization.product_catalog_enabled?

      metered_item_selections.present? && metered_item_selections.all? do |selection|
        already_processed?(selection.metered_item)
      end
    end

    def already_processed?(metered_item = nil)
      if event.organization.product_catalog_enabled?
        @processed_contract_rate_card_ids ||= Fee.from_organization(event.organization)
          .where(pay_in_advance_event_transaction_id: event.transaction_id)
          .pluck(:contract_rate_card_id)
          .to_set

        return @processed_contract_rate_card_ids.include?(metered_item.contract_rate_card.id)
      end

      return @charges_already_processed if defined?(@charges_already_processed)

      @charges_already_processed = Fee.from_organization_pay_in_advance(event.organization)
        .where(pay_in_advance_event_transaction_id: event.transaction_id)
        .exists?
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
