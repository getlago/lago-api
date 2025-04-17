# frozen_string_literal: true

class ActivityLogsQuery < BaseQuery
  Result = BaseResult[:activity_logs]
  Filters = BaseFilters[
    :from_date,
    :to_date,
    :activity_types,
    :activity_sources,
    :user_emails,
    :external_customer_id,
    :external_subscription_id,
    :resource_id,
    :resource_type
  ]

  MAX_AGE = 30.days

  def call
    activity_logs = Clickhouse::ActivityLog.where(organization_id: organization.id, logged_at: MAX_AGE.ago..)
    activity_logs = paginate(activity_logs)
    activity_logs = activity_logs.order(logged_at: :desc)

    activity_logs = with_logged_at_range(activity_logs) if filters.from_date || filters.to_date
    activity_logs = with_activity_types(activity_logs) if filters.activity_types.present?
    activity_logs = with_activity_sources(activity_logs) if filters.activity_sources.present?
    activity_logs = with_user_emails(activity_logs) if filters.user_emails.present?
    activity_logs = with_external_customer_id(activity_logs) if filters.external_customer_id.present?
    activity_logs = with_external_subscription_id(activity_logs) if filters.external_subscription_id.present?
    activity_logs = with_resource_id(activity_logs) if filters.resource_id.present?
    activity_logs = with_resource_type(activity_logs) if filters.resource_type.present?

    result.activity_logs = activity_logs
    result
  end

  private

  def with_logged_at_range(scope)
    scope = scope.where(logged_at: from_date..) if filters.from_date
    scope = scope.where(logged_at: ..to_date) if filters.to_date
    scope
  end

  def with_activity_types(scope)
    scope.where(activity_type: filters.activity_types)
  end

  def with_activity_sources(scope)
    scope.where(activity_source: filters.activity_sources)
  end

  def with_user_emails(scope)
    user_ids = organization.users.where(email: filters.user_emails).pluck(:id)
    scope.where(user_id: user_ids)
  end

  def with_external_customer_id(scope)
    scope.where(external_customer_id: filters.external_customer_id)
  end

  def with_external_subscription_id(scope)
    scope.where(external_subscription_id: filters.external_subscription_id)
  end

  def with_resource_id(scope)
    scope.where(resource_id: filters.resource_id)
  end

  def with_resource_type(scope)
    scope.where(resource_type: filters.resource_type)
  end

  def from_date
    @from_date ||= parse_datetime_filter(:from_date)
  end

  def to_date
    @to_date ||= parse_datetime_filter(:to_date)
  end
end
