# frozen_string_literal: true

module Events
  class ReEnrichService < BaseService
    Result = BaseResult[]

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    def call
      EnrichedEvent.transaction do
        drop_enriched_events

        # Process subscription events in batches
        events.find_in_batches do |events|
          enriched = events.map do |event|
            billable_metric = billable_metrics[event.code]
            next [] unless billable_metric

            charges_and_filters = charges[event.code]
              .index_with { |c| ChargeFilters::EventMatchingService.call(charge: c, event:).charge_filter }

            # Only returns unpersisted enriched events
            Events::EnrichService
              .call!(event:, subscription:, billable_metric:, charges_and_filters:, persist: false)
              .enriched_events
          end

          # Batch insert enriched events
          attributes = enriched.flatten.map { |ev| ev.attributes.without("id") }
          EnrichedEvent.insert_all(attributes) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :timestamp

    def boundaries
      return @boundaries if @boundaries

      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        timestamp,
        current_usage: true
      )

      @boundaries = BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days,
        timestamp:
      )
    end

    def drop_enriched_events
      EnrichedEvent
        .where(organization_id: subscription.organization_id, subscription_id: subscription.id)
        .where(timestamp: boundaries.charges_from_datetime...boundaries.charges_to_datetime)
        .delete_all
    end

    def events
      Event.where(organization_id: subscription.organization_id)
        .where(external_subscription_id: subscription.external_id)
        .where(timestamp: boundaries.charges_from_datetime...boundaries.charges_to_datetime)
    end

    def billable_metrics
      @billable_metrics ||= subscription.plan.billable_metrics.index_by(&:code)
    end

    def charges
      @charges ||= subscription.plan.charges
        .includes(:billable_metric, filters: {values: :billable_metric_filter})
        .group_by { it.billable_metric.code }
    end
  end
end
