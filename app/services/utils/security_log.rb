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
    # @param api_key [ApiKey, nil] the API key used for the action
    # @param resources [Hash] additional context (e.g., {invitee_email: "..."})
    # @param device_info [Hash] device metadata for login events
    # @return [Boolean] true if log was produced, false otherwise
    def self.produce(
      organization:,
      log_type:,
      log_event:,
      user: nil,
      api_key: nil,
      resources: {},
      device_info: {}
    )
      return false unless available?
      return false unless organization.security_logs_enabled?

      current_time = Time.current.iso8601[...-1]

      Karafka.producer.produce_async(
        topic: ENV["LAGO_KAFKA_SECURITY_LOGS_TOPIC"],
        key: "#{organization.id}--#{SecureRandom.uuid}",
        payload: {
          organization_id: organization.id,
          user_id: user&.id,
          api_key_id: api_key&.id,
          log_id: SecureRandom.uuid,
          log_type:,
          log_event:,
          device_info: device_info.transform_keys(&:to_s),
          resources: resources.transform_keys(&:to_s),
          logged_at: current_time,
          created_at: current_time
        }.to_json
      )

      true
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
