# frozen_string_literal: true

module Middlewares
  module Yabeda
    class DurationMiddleware < BaseMiddleware
      # Registers a histogram metric for operation durations.
      def self.on_use(operation:)
        ::Yabeda.configure do
          group :lago do
            histogram :"#{operation}_duration",
              buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 3.0, 10.0],
              comment: "Duration of #{operation}"
          end
        end
      end

      def before_call
        @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def after_call(result)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
        operation = service_instance.class.name.underscore.tr("/", "_")
        ::Yabeda.lago.public_send(:"#{operation}_duration").measure({}, duration)
      end
    end
  end
end
