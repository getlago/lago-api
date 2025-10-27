# frozen_string_literal: true

class EventsQuery < BaseQuery
  Result = BaseResult[:events]
  Filters = BaseFilters[
    :code,
    :external_subscription_id,
    :timestamp_from_started_at,
    :timestamp_from,
    :timestamp_to
  ]

  def call
    events = organization.clickhouse_events_store? ? Clickhouse::EventsRaw : Event
    events = events.where(organization_id: organization.id)
    events = paginate(events)

    events = events.order(timestamp: :desc) unless organization.clickhouse_events_store?
    events = events.order(ingested_at: :desc) if organization.clickhouse_events_store?

    events = with_code(events) if filters.code
    events = with_external_subscription_id(events) if filters.external_subscription_id
    events = with_timestamp_range(events)

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
    if timestamp_from_started_at? && subscription
      scope = scope.where(timestamp: subscription.started_at..)
    elsif filters.timestamp_from
      scope = scope.where(timestamp: timestamp_from..)
    end

    scope = scope.where(timestamp: ..timestamp_to) if filters.timestamp_to

    scope
  end

  def subscription
    @subscription ||= organization.subscriptions
      .order("terminated_at DESC NULLS FIRST, started_at DESC")
      .find_by(
        external_id: filters.external_subscription_id
      )
  end

  def timestamp_from
    @timestamp_from ||= parse_datetime_filter(:timestamp_from)
  end

  def timestamp_to
    @timestamp_to ||= parse_datetime_filter(:timestamp_to)
  end

  def timestamp_from_started_at?
    ActiveModel::Type::Boolean.new.cast(filters.timestamp_from_started_at)
  end
end
