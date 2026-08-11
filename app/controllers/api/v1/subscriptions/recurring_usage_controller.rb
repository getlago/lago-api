# frozen_string_literal: true

module Api
  module V1
    module Subscriptions
      class RecurringUsageController < BaseController
        def terminate
          result = ::Subscriptions::TerminateRecurringUsageService.call(
            subscription:,
            params: input_params,
            metadata: event_metadata
          )

          if result.success?
            render(
              json: ::V1::EventSerializer.new(
                result.event,
                root_name: "event"
              )
            )
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "subscription"
        end

        def input_params
          params
            .require(:recurring_usage)
            .permit(
              :billable_metric_code,
              :charge_code,
              :transaction_id,
              :timestamp,
              group: {}
            )
        end

        def event_metadata
          {
            user_agent: request.user_agent,
            ip_address: request.remote_ip
          }
        end
      end
    end
  end
end
