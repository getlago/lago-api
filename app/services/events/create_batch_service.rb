# frozen_string_literal: true

module Events
  class CreateBatchService < BaseService
    MAX_LENGTH = ENV.fetch("LAGO_EVENTS_BATCH_MAX_LENGTH", 100).to_i

    def initialize(organization:, events_params:, timestamp:, metadata:)
      @organization = organization
      @events_params = events_params[:events]
      @timestamp = timestamp
      @metadata = metadata

      super
    end

    def call
      if events_params.count > MAX_LENGTH
        return result.single_validation_failure!(error_code: 'too_many_events', field: :events)
      end

      validate_events

      return result.validation_failure!(errors: result.errors) if result.errors.present?

      post_validate_events

      result
    end

    private

    attr_reader :organization, :events_params, :timestamp, :metadata

    def validate_events
      result.events = []
      result.errors = {}

      events_params.each_with_index do |event_params, index|
        event = Event.new
        event.organization_id = organization.id
        event.code = event_params[:code]
        event.transaction_id = event_params[:transaction_id]
        event.external_subscription_id = event_params[:external_subscription_id]
        event.properties = event_params[:properties] || {}
        event.metadata = metadata || {}
        event.timestamp = Time.zone.at(event_params[:timestamp] ? event_params[:timestamp].to_f : timestamp)

        result.events.push(event)
        result.errors = result.errors.merge({index => event.errors.messages}) unless event.valid?
      end
    end

    def post_validate_events
      ActiveRecord::Base.transaction do
        result.events.each(&:save!)
      end

      result.events.each do |event|
        produce_kafka_event(event)
        Events::PostProcessJob.perform_later(event:)
      end
    end

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
          timestamp: event.timestamp.to_f,
          code: event.code,
          properties: event.properties,
          ingested_at: Time.zone.now.iso8601[...-1]
        }.to_json
      )
    end
  end
end
