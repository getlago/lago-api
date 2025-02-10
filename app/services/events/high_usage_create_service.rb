# frozen_string_literal: true

module Events
  class HighUsageCreateService < BaseService
    Result = BaseResult[:transaction_id]

    def initialize(organization:, params:, timestamp:)
      @organization = organization
      @params = params
      @timestamp = timestamp
      super
    end

    def call
      return result.not_allowed_failure!(code: "missing_configuration") if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return result.not_allowed_failure!(code: "missing_configuration") if ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"].blank?

      Karafka.producer.produce_async(
        topic: ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"],
        key: "#{organization.id}-#{params[:external_subscription_id]}",
        payload: {
          organization_id: organization.id,
          external_subscription_id: params[:external_subscription_id],
          transaction_id: params[:transaction_id],
          timestamp: params[:timestamp].presence || timestamp.to_i,
          code: params[:code],
          # NOTE: Default value to 0.0 is required for clickhouse parsing
          precise_total_amount_cents:,
          properties: params[:properties] || {},
          # NOTE: Removes trailing 'Z' to allow clickhouse parsing
          ingested_at: Time.current.iso8601[...-1],
          source: "http_ruby_high_usage"
        }.to_json
      )

      result.transaction_id = params[:transaction_id]
      result
    end

    private

    attr_reader :organization, :params, :timestamp

    def precise_total_amount_cents
      BigDecimal(params[:precise_total_amount_cents].presence || "0.0").to_s
    rescue ArgumentError
      "0.0"
    end
  end
end
