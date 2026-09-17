# frozen_string_literal: true

module EventDestinations
  module DeliveryLogger
    PREFIX = "[streaming] event=delivery"

    OUTCOMES = {
      delivered: :info,
      throttled: :error,
      dropped: :error,
      superseded: :info,
      skipped: :warn,
      failed: :error
    }.freeze

    SAFE_VALUE = /\A[\w.:@\/+-]*\z/

    class << self
      def emit(outcome, destination: nil, **fields)
        Rails.logger.public_send(OUTCOMES.fetch(outcome), line(outcome, destination, fields))
      end

      private

      def line(outcome, destination, fields)
        pairs = {outcome:}

        if destination
          pairs[:destination_id] = destination.id
          pairs[:organization_id] = destination.organization_id
        end

        pairs.merge!(fields.compact)

        "#{PREFIX} #{pairs.map { |key, value| "#{key}=#{format_value(value)}" }.join(" ")}"
      end

      def format_value(value)
        string = value.to_s

        string.match?(SAFE_VALUE) ? string : string.inspect
      end
    end
  end
end
