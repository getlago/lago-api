# frozen_string_literal: true

module Api
  module V1
    class EventsController < Api::BaseController
      def create
        result = ::Events::CreateService.call(
          organization: current_organization,
          params: create_params,
          timestamp: Time.current.to_f,
          metadata: event_metadata
        )

        if result.success?
          render(
            json: ::V1::EventSerializer.new(
              result.event,
              root_name: 'event'
            )
          )
        else
          render_error_response(result)
        end
      end

      def batch
        result = ::Events::CreateBatchService.call(
          organization: current_organization,
          events_params: batch_params,
          timestamp: Time.current.to_f,
          metadata: event_metadata
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.events,
              ::V1::EventSerializer,
              collection_name: 'events'
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        event_scope = current_organization.clickhouse_events_store? ? Clickhouse::EventsRaw : Event
        event = event_scope.find_by(
          organization: current_organization,
          transaction_id: params[:id]
        )

        return not_found_error(resource: 'event') unless event

        render(
          json: ::V1::EventSerializer.new(
            event,
            root_name: 'event'
          )
        )
      end

      def index
        result = EventsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: index_filters
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.events,
              ::V1::EventSerializer,
              collection_name: 'events',
              meta: pagination_metadata(result.events)
            )
          )
        else
          render_error_response(result)
        end
      end

      def estimate_fees
        result = Fees::EstimatePayInAdvanceService.call(
          organization: current_organization,
          params: create_params
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.fees,
              ::V1::FeeSerializer,
              collection_name: 'fees',
              includes: %i[applied_taxes]
            )
          )
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

      def index_filters
        params.permit(
          :code,
          :external_subscription_id,
          :timestamp_from,
          :timestamp_to
        )
      end

      def event_metadata
        {
          user_agent: request.user_agent,
          ip_address: request.remote_ip
        }
      end

      def track_api_key_usage?
        action_name&.to_sym != :create
      end
    end
  end
end
