# frozen_string_literal: true

module Events
  class CreateService < BaseService
    def initialize(organization:, params:, timestamp:, metadata:)
      @organization = organization
      @params = params
      @timestamp = timestamp
      @metadata = metadata
      super
    end

    def call
      event = Event.new
      event.organization_id = organization.id
      event.code = params[:code]
      event.transaction_id = params[:transaction_id]
      event.external_subscription_id = params[:external_subscription_id]
      event.properties = params[:properties] || {}
      event.metadata = metadata || {}
      event.timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_f : timestamp)
      event.precise_total_amount_cents = params[:precise_total_amount_cents]

      pre_ingest(event, params)

      event.save! unless organization.clickhouse_aggregation?

      result.event = event

      produce_kafka_event(event)
      Events::PostProcessJob.perform_later(event:) unless organization.clickhouse_aggregation?

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :transaction_id, error_code: 'value_already_exist')
    end

    private

    def pre_ingest(event, params)
      billable_metric = organization.billable_metrics.find_by(code: params[:code])
      return if billable_metric.expression.blank?

      parser = LagoFormulaParser.new
      result = parser.parse(billable_metric.expression)
      value = result.evaluate(event.properties)
      if value.is_a? Numeric
        event.value_numeric = value.to_d
      end

      event.value = value.to_s
    end

    attr_reader :organization, :params, :timestamp, :metadata

    def produce_kafka_event(event)
      return if ENV['LAGO_KAFKA_BOOTSTRAP_SERVERS'].blank?
      return if ENV['LAGO_KAFKA_RAW_EVENTS_TOPIC'].blank?

      Karafka.producer.produce_async(
        topic: ENV['LAGO_KAFKA_RAW_EVENTS_TOPIC'],
        key: "#{organization.id}-#{event.external_subscription_id}",
        payload: {
          organization_id: organization.id,
          external_customer_id: event.external_customer_id,
          external_subscription_id: event.external_subscription_id,
          transaction_id: event.transaction_id,
          timestamp: event.timestamp.iso8601[...-1], # NOTE: Removes trailing 'Z' to allow clickhouse parsing
          code: event.code,
          precise_total_amount_cents: event.precise_total_amount_cents,
          properties: event.properties,
          ingested_at: Time.zone.now.iso8601[...-1]
        }.to_json
      )
    end
  end
end
