# frozen_string_literal: true

class SecurityLogsQuery < BaseQuery
  Result = BaseResult[:security_logs]
  Filters = BaseFilters[
    :from_date,
    :to_date,
    :user_ids,
    :log_types,
    :log_events
  ]

  def call
    return result.forbidden_failure! unless self.class.available?
    return result.forbidden_failure! unless organization.security_logs_enabled?

    # TODO: the stub returns the empty collection. Should be changed after implementation of Clickhouse::SecurityLog
    result.security_logs = paginate(Kaminari.paginate_array([]))
    result
  end

  def self.available?
    ENV["LAGO_CLICKHOUSE_ENABLED"].present?
  end
end
