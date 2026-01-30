# frozen_string_literal: true

module Utils
  # Produces security log events to Kafka for ClickHouse consumption.
  #
  # Security logs track user and system configuration changes:
  # user management, role changes, API key rotations, webhook configuration.
  #
  # Unlike Activity Logs, Security Logs:
  # - Do not track customer/subscription data
  # - Use flat resources map instead of polymorphic resource
  # - Require per-org premium integration (not just global `License.premium?`)
  # - Are collected ONLY for cloud Premium organizations
  class SecurityLog
    # Produces a security log event to Kafka.
    #
    # @param organization [Organization] the organization context
    # @param log_type [String] event category (e.g. "user", or "api_key")
    # @param log_event [String] specific event (e.g. "user.invited")
    # @param user [User, nil] the user who performed the action (nil for API key operations)
    # @param resources [Hash] additional context (e.g., {invitee_email: "..."})
    # @param device_info [Hash] device metadata for login events
    # @return [Boolean] true if log was produced, false otherwise
    def self.produce(
      organization:,
      log_type:,
      log_event:,
      user: nil,
      resources: {},
      device_info: {}
    )
      # Stub implementation
      available?
    end

    # Checks if security logging infrastructure is available.
    #
    # @return [Boolean] true if ClickHouse, Kafka and topic are configured
    def self.available?
      ENV["LAGO_CLICKHOUSE_ENABLED"].present? &&
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].present? &&
        ENV["LAGO_KAFKA_SECURITY_LOGS_TOPIC"].present?
    end
  end
end
