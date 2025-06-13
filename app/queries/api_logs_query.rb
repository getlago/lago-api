# frozen_string_literal: true

class ApiLogsQuery < BaseQuery
  Result = BaseResult[:api_logs]
  Filters = BaseFilters[
    :from_date,
    :to_date,
    :http_methods,
    :http_statuses,
    :api_version,
    :api_key_ids,
    :request_paths
  ]

  MAX_AGE = 30.days

  def call
    api_logs = Clickhouse::ApiLog.where(organization_id: organization.id, logged_at: MAX_AGE.ago..)
    api_logs = api_logs.order(logged_at: :desc)

    api_logs = with_logged_at_range(api_logs) if filters.from_date || filters.to_date
    api_logs = with_api_key_ids(api_logs) if filters.api_key_ids.present?
    api_logs = with_http_statuses(api_logs) if filters.http_statuses.present?
    api_logs = with_http_methods(api_logs) if filters.http_methods.present?
    api_logs = with_api_version(api_logs) if filters.api_version.present?
    api_logs = with_request_paths(api_logs) if filters.request_paths.present?

    Clickhouse::ApiLog.transaction do
      Clickhouse::ApiLog.connection.execute("SELECT 1 SETTINGS max_execution_time=5000") if filters.request_paths.present?

      api_logs = paginate(api_logs)
      result.api_logs = api_logs
      result
    end
  end

  private

  def with_logged_at_range(scope)
    scope = scope.where(logged_at: filters.from_date..) if filters.from_date
    scope = scope.where(logged_at: ..filters.to_date) if filters.to_date
    scope
  end

  def with_api_key_ids(scope)
    scope.where(api_key_id: filters.api_key_ids)
  end

  def with_http_methods(scope)
    scope.where(http_method: filters.http_methods)
  end

  def with_http_statuses(scope)
    if (filters.http_statuses & %w[succeeded failed]).any?
      scope = scope.where("http_status <= ?", 399) if filters.http_statuses.include?("succeeded")
      scope = scope.where("http_status > ?", 399) if filters.http_statuses.include?("failed")
    else
      # TODO: Improve that to return nothing if filters.http_statuses is not a valid value
      scope = scope.where(http_status: filters.http_statuses)
    end
    scope
  end

  def with_api_version(scope)
    scope.where(api_version: filters.api_version)
  end

  def with_request_paths(scope)
    scope.where("match(request_path, ?)", filters.request_paths)
  end
end
