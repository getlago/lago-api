# frozen_string_literal: true

class EventsQuery < BaseQuery
  def call
    events = organization.clickhouse_events_store? ? Clickhouse::EventsRaw : Event
    events = events.where(organization_id: organization.id)
    events = paginate(events)

    events = events.order(created_at: :desc) unless organization.clickouse_events_store?

    events = with_code(events) if filters.code
    events = with_external_subscription_id(events) if filters.external_subscription_id
    events = with_timestamp_range(events) if filters.timestamp_from || filters.timestamp_to

    result.events = events
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def with_code(scope)
    scope.where(code: filters.code)
  end

  def with_external_subscription_id(scope)
    scope.where(external_subscription_id: filters.external_subscription_id)
  end

  def with_timestamp_range(scope)
    scope = scope.where(timestamp: timestamp_from..) if filters.timestamp_from
    scope = scope.where(timestamp: ..timestamp_to) if filters.timestamp_to
    scope
  end

  def timestamp_from
    @timestamp_from ||= parse_datetime_filter(:timestamp_from)
  end

  def timestamp_to
    @timestamp_to ||= parse_datetime_filter(:timestamp_to)
  end
end
