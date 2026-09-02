# frozen_string_literal: true

module EventDestinations
  module CustomerUsage
    class RefreshedService < BaseService
      Result = BaseResult

      EVENT_TYPE = "customer_usage.refreshed"
      OBJECT_TYPE = "customer_usage"

      def initialize(object:)
        @customer = object

        super
      end

      def call
        return result if stream.nil?

        customer.active_subscriptions.each do |subscription|
          deliver(subscription)
        rescue => e
          Rails.logger.error(
            "[event_destinations] #{EVENT_TYPE} failed for subscription #{subscription.id}: #{e.class} #{e.message}"
          )
        end

        result
      end

      private

      attr_reader :customer

      def stream
        return @stream if defined?(@stream)

        @stream = EventDestinations::KinesisStream.for(customer.organization)
      end

      def producer
        @producer ||= EventDestinations::KinesisProducer.new(stream:)
      end

      def deliver(subscription)
        usage_result = ::Invoices::CustomerUsageService.call(customer:, subscription:, with_cache: true)

        unless usage_result.success?
          Rails.logger.warn(
            "[event_destinations] #{EVENT_TYPE} skipped for subscription #{subscription.id}: #{usage_result.error}"
          )
          return
        end

        producer.produce(data: envelope(subscription, usage_result.usage), partition_key: customer.external_id)
      end

      # Webhook-shaped envelope, plus the identifiers a consumer needs and that the usage
      # payload itself does not carry.
      def envelope(subscription, usage)
        {
          webhook_type: EVENT_TYPE,
          object_type: OBJECT_TYPE,
          organization_id: customer.organization_id,
          customer_external_id: customer.external_id,
          subscription_external_id: subscription.external_id,
          version:,
          customer_usage: serialized_usage(usage)
        }
      end

      # Monotonic per customer because DeliverEventJob serializes on the customer. Fixed-width
      # UTC ISO8601 so consumers can compare it as a string. One token per delivery: the two
      # records of a customer are different dedup keys, so they may share it.
      def version
        @version ||= Time.current.iso8601(6)
      end

      def serialized_usage(usage)
        ::V1::Customers::UsageSerializer.new(
          usage,
          root_name: OBJECT_TYPE,
          includes: %i[charges_usage]
        ).serialize
      end
    end
  end
end
