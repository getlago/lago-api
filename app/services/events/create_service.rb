# frozen_string_literal: true

module Events
  class CreateService < BaseService
    Result = BaseResult[:event]

    def initialize(organization:, params:, timestamp:, metadata:)
      @organization = organization
      @params = params
      @timestamp = timestamp
      @metadata = metadata
      super
    end

    def call
      event_timestamp = parse_timestamp
      return result.single_validation_failure!(field: :timestamp, error_code: "invalid_format") unless event_timestamp

      event = Event.new
      event.organization_id = organization.id
      event.code = params[:code]
      event.transaction_id = params[:transaction_id]
      # external_contract_id is the v2 alias: a catalog org addresses its
      # agreement by contract id, a legacy org by subscription id. Single-engine
      # orgs carry one, and the event always stores it under
      # external_subscription_id; an explicit external_subscription_id wins.
      event.external_subscription_id = params[:external_subscription_id].presence || params[:external_contract_id]
      event.properties = params[:properties] || {}
      event.metadata = metadata || {}
      event.timestamp = event_timestamp
      event.precise_total_amount_cents = params[:precise_total_amount_cents]

      expression_result = CalculateExpressionService.call(organization:, event:)
      return result.validation_failure!(errors: expression_result.error.message) unless expression_result.success?

      event.save! unless organization.clickhouse_events_store?

      result.event = event

      # Enqueued before producing to Kafka so that a failed enqueue leaves nothing behind
      # downstream either.
      enqueue_post_process(event) unless organization.clickhouse_events_store?
      produce_kafka_event(event)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :transaction_id, error_code: "value_already_exist")
    end

    private

    attr_reader :organization, :params, :timestamp, :metadata

    def parse_timestamp
      Time.zone.at(params[:timestamp] ? BigDecimal(params[:timestamp].to_s) : timestamp)
    rescue ArgumentError
      nil
    end

    def produce_kafka_event(event)
      Events::KafkaProducerService.call!(events: event, organization:)
    end

    def enqueue_post_process(event)
      Events::PostProcessJob.perform_later(event:)
    rescue
      # Hard-deleted rather than discarded: `index_unique_transaction_id` carries no `deleted_at`
      # predicate, so a discarded event would keep refusing the caller's retry.
      event.delete
      raise
    end
  end
end
