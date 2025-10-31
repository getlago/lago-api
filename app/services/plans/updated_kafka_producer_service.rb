# frozen_string_literal: true

module Plans
  class UpdatedKafkaProducerService < BaseService
    Result = BaseResult

    def initialize(plan:, resources_type:, resources_ids:, event_type:, timestamp:)
      @plan = plan
      @resources_type = resources_type
      @resources_ids = resources_ids
      @event_type = event_type
      @timestamp = timestamp
      super
    end

    def call
      return result if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return result if ENV["LAGO_KAFKA_PLAN_CONFIG_UPDATED_TOPIC"].blank?
      return result unless organization.clickhouse_live_aggregation_enabled?

      Karafka.producer.produce_async(
        topic: ENV["LAGO_KAFKA_PLAN_CONFIG_UPDATED_TOPIC"],
        key: "#{organization.id}-#{plan.id}",
        payload: {
          organization_id: organization.id,
          plan_id: plan.id,
          resources_ids:,
          resources_type:,
          event_type:,
          timestamp: timestamp.iso8601(3),
          produced_at: Time.current.iso8601
        }
      )

      result
    end

    private

    attr_reader :plan, :resources_type, :resources_ids, :event_type, :timestamp

    delegate :organization, to: :plan
  end
end
