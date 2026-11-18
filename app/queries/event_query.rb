# frozen_string_literal: true

class EventQuery < BaseQuery
  Result = BaseResult[:event]
  Filters = BaseFilters[
    :transaction_id,
    :external_subscription_id,
    :code,
    :timestamp
  ]

  def self.event_model(organization:)
    if !organization.clickhouse_events_store?
      Event
    elsif organization.product_events_pipeline?
      Clickhouse::ProductEventsRaw
    else
      Clickhouse::EventsRaw
    end
  end

  def call
    return result.single_validation_failure!(field: :transaction_id, error_code: "value_is_mandatory") if filters.transaction_id.blank?

    result.event = scope.order(order_column => :desc).first
    result
  end

  private

  def scope
    events = event_model
      .where(organization_id: organization.id, transaction_id: filters.transaction_id)

    events = events.where(external_subscription_id: filters.external_subscription_id) if filters.external_subscription_id.present?
    events = with_code(events) if filters.code.present?
    events = with_timestamp(events) if filters.timestamp.present?

    events
  end

  def with_code(events)
    events.where(code: filters.code)
  end

  # Only meaningful on the Clickhouse store: index_unique_transaction_id already makes
  # (organization_id, external_subscription_id, transaction_id) unique in Postgres, and the
  # column there holds microseconds, which a millisecond filter could not address.
  def with_timestamp(events)
    return events unless clickhouse_events?

    events.where(timestamp: filters.timestamp)
  end

  def event_model
    self.class.event_model(organization:)
  end

  def order_column
    clickhouse_events? ? :ingested_at : :created_at
  end

  def clickhouse_events?
    organization.clickhouse_events_store?
  end
end
