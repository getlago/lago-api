# frozen_string_literal: true

module EventDestinations
  module CustomerUsage
    class RefreshedService < BaseService
      Result = BaseResult

      EVENT_TYPE = "customer_usage.refreshed"
      OBJECT_TYPE = "customer_usage"
      SCHEMA_VERSION = 1

      def initialize(object:)
        @customer = object

        super
      end

      def call
        return result if destination.nil?

        customer.active_subscriptions.each do |subscription|
          deliver(subscription)
        rescue => e
          log(:failed, subscription, error: e.class, message: e.message)
        end

        result
      end

      private

      attr_reader :customer

      def destination
        return @destination if defined?(@destination)

        @destination = StreamingDestinations::KinesisDestination
          .for_event(customer.organization, EVENT_TYPE)
          .first
      end

      def producer
        @producer ||= EventDestinations::KinesisProducer.new(destination:)
      end

      def deliver(subscription)
        usage_result = ::Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: true
        )

        unless usage_result.success?
          log(:skipped, subscription, error: usage_result.error.class, message: usage_result.error)
          return
        end

        producer.produce(
          data: envelope(subscription, usage_result.usage),
          partition_key: partition_key_for(subscription)
        )
      end

      def log(outcome, subscription, **fields)
        EventDestinations::DeliveryLogger.emit(
          outcome,
          destination:,
          event_type: EVENT_TYPE,
          customer_id: customer.id,
          subscription_id: subscription.id,
          **fields
        )
      end

      def envelope(subscription, usage)
        {
          schema_version: SCHEMA_VERSION,
          event_id: SecureRandom.uuid_v7,
          event_type: EVENT_TYPE,
          object_type: OBJECT_TYPE,
          organization_id: customer.organization_id,
          customer_external_id: customer.external_id,
          subscription_external_id: subscription.external_id,
          version:,
          customer_usage: serialized_usage(usage)
        }
      end

      def partition_key_for(_subscription)
        case destination.partition_key
        when StreamingDestinations::KinesisDestination::PARTITION_KEY_CUSTOMER_EXTERNAL_ID
          customer.external_id
        else
          raise ArgumentError, "unsupported partition key #{destination.partition_key.inspect}"
        end
      end

      def version
        @version ||= Time.current.utc.iso8601(6)
      end

      def serialized_usage(usage)
        EventDestinations::CustomerUsageSerializer.new(usage, root_name: OBJECT_TYPE).serialize
      end
    end
  end
end
