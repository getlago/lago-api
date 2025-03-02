# frozen_string_literal: true

module Api
  module V2
    class EventsController < Api::BaseController
      # NOTE: This controller is experimental, and might change in the future
      #       Do not rely on it for production purpose for now

      def create
        result = ::Events::HighUsageCreateService.call(
          organization: current_organization,
          params: create_params,
          timestamp: Time.current.to_f
        )

        if result.success?
          render(json: {event: {transaction_id: result.transaction_id}})
        else
          render_error_response(result)
        end
      end

      def batch
        result = ::Events::HighUsageBatchCreateService.call(
          organization: current_organization,
          params: batch_params[:events],
          timestamp: Time.current.to_f
        )

        if result.success?
          render(json: {events: result.transactions})
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params
          .require(:event)
          .permit(
            :transaction_id,
            :code,
            :timestamp,
            :external_subscription_id,
            :precise_total_amount_cents,
            properties: {}
          )
      end

      def batch_params
        params
          .permit(
            events: [
              :transaction_id,
              :code,
              :timestamp,
              :external_subscription_id,
              :precise_total_amount_cents,
              properties: {} # rubocop:disable Style/HashAsLastArrayItem
            ]
          ).to_h.deep_symbolize_keys
      end

      def track_api_key_usage?
        action_name&.to_sym != :create
      end

      def resource_name
        "event"
      end

      def cached_api_key?
        true
      end
    end
  end
end
