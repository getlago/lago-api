# frozen_string_literal: true

module Api
  module V2
    class EventsController < BaseController
      EVENT_FIELDS = %i[transaction_id code timestamp external_contract_id precise_total_amount_cents].freeze

      skip_audit_logs!

      serializable_with ::V2::EventSerializer

      before_action :ensure_product_event_pipeline!, only: %i[create batch]
      before_action :reject_unsupported_filters!, only: :index

      def index
        result = ::V2::EventsQuery.call(organization: current_organization, pagination: cursor, filters: index_filters)

        if result.success?
          render_events(result.events)
        else
          render_error_response(result)
        end
      end

      def create
        params.expect(event: {})
        validation = ::Events::ValidateApiInputService.call(params: raw_input[:event])
        return render_error_response(validation) unless validation.success?

        result = ::Events::CreateService.call(
          organization: current_organization,
          params: event_params,
          timestamp: Time.current.to_f,
          metadata: event_metadata,
          catalog_events: true
        )

        if result.success?
          render_event(result.event)
        else
          render_error_response(result)
        end
      end

      def batch
        validation = ::Events::ValidateApiInputService.call(params: raw_input[:events], batch: true)
        return render_error_response(validation) unless validation.success?

        result = ::Events::CreateBatchService.call(
          organization: current_organization,
          events_params: batch_params,
          timestamp: Time.current.to_f,
          metadata: event_metadata,
          catalog_events: true
        )

        if result.success?
          render_events(result.events)
        else
          render_error_response(result)
        end
      end

      private

      # The read store and cursor order depend on the organization's event storage.
      def paginated_model
        ::V2::EventsQuery.event_model(organization: current_organization)
      end

      def paginated_sort
        ::V2::EventsQuery.cursor_sort(organization: current_organization)
      end

      def index_filters
        params.slice(:code, :transaction_id, :external_contract_id, :timestamp_from_started_at,
          :timestamp_from, :timestamp_to).to_unsafe_h.symbolize_keys
      end

      def reject_unsupported_filters!
        unsupported_filters = params.slice(:external_subscription_id, :created_at_from, :created_at_to).keys

        if unsupported_filters.any?
          validation_errors(errors: unsupported_filters.index_with { ["value_is_invalid"] })
        end
      end

      def event_params
        raw_params.require(:event).permit(*EVENT_FIELDS, properties: {})
      end

      def batch_params
        raw_params.permit(events: [*EVENT_FIELDS, {properties: {}}])
      end

      def raw_params
        ActionController::Parameters.new(raw_input)
      end

      # Rails removes null array entries before strong parameters; validate the original batch.
      def raw_input
        @raw_input ||= if request.content_mime_type == Mime[:json] && request.raw_post.present?
          body = JSON.parse(request.raw_post)
          body.is_a?(Hash) ? NullByteGuard.sanitize(request, body).deep_symbolize_keys : {}
        else
          params.to_unsafe_h.deep_symbolize_keys
        end
      end

      def event_metadata
        {user_agent: request.user_agent, ip_address: request.remote_ip}
      end

      def ensure_product_event_pipeline!
        if current_organization.clickhouse_events_store? &&
            (ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank? || ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"].blank?)
          forbidden_error(code: "endpoint_not_available")
        end
      end

      def track_api_key_usage?
        action_name != "create"
      end

      def cached_api_key?
        %w[create batch].include?(action_name)
      end

      def resource_name
        "event"
      end
    end
  end
end
