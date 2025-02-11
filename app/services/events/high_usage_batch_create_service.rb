# frozen_string_literal: true

module Events
  class HighUsageBatchCreateService < BaseService
    Result = BaseResult[:transactions]

    MAX_LENGTH = ENV.fetch("LAGO_EVENTS_BATCH_MAX_LENGTH", 100).to_i

    def initialize(organization:, params:, timestamp:)
      @organization = organization
      @params = params
      @timestamp = timestamp
      super
    end

    def call
      return result.not_allowed_failure!(code: "missing_configuration") if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return result.not_allowed_failure!(code: "missing_configuration") if ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"].blank?

      if params.blank?
        return result.single_validation_failure!(error_code: "no_events", field: :events)
      end

      if params.count > MAX_LENGTH
        return result.single_validation_failure!(error_code: "too_many_events", field: :events)
      end

      process_events

      result.transactions = params.map { {transaction_id: _1[:transaction_id]} }
      result
    end

    private

    attr_reader :organization, :params, :timestamp

    def process_events
      payloads = params.map do |event_params|
        {
          topic: ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"],
          key: "#{organization.id}-#{event_params[:external_subscription_id]}",
          payload: {
            organization_id: organization.id,
            external_subscription_id: event_params[:external_subscription_id],
            transaction_id: event_params[:transaction_id],
            timestamp: parsed_timestamp(event_params[:timestamp]),
            code: event_params[:code],
            # NOTE: Default value to 0.0 is required for clickhouse parsing
            precise_total_amount_cents: precise_total_amount_cents(event_params[:precise_total_amount_cents]),
            properties: event_params[:properties] || {},
            # NOTE: Removes trailing 'Z' to allow clickhouse parsing
            ingested_at: Time.current.iso8601[...-1],
            source: "http_ruby_high_usage"
          }.to_json
        }
      end

      Karafka.producer.produce_many_sync(payloads)
    end

    def precise_total_amount_cents(precise_total_amount_cents)
      BigDecimal(precise_total_amount_cents.presence || "0.0").to_s
    rescue ArgumentError
      "0.0"
    end

    def parsed_timestamp(event_timestamp)
      Time.zone.at(event_timestamp ? Float(event_timestamp) : timestamp).to_i
    rescue ArgumentError
      timestamp.to_i
    end
  end
end
