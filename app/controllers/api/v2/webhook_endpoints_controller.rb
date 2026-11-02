# frozen_string_literal: true

module Api
  module V2
    class WebhookEndpointsController < Api::V2::BaseController
      cursor_paginated_index(WebhookEndpoint)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::WebhookEndpointSerializer

      def index
        result = ::WebhookEndpointsQuery.call(organization: current_organization, pagination: cursor, filters: date_range_filters)

        if result.success?
          render_webhook_endpoints(result.webhook_endpoints)
        else
          render_error_response(result)
        end
      end

      def show
        webhook_endpoint = find_webhook_endpoint

        if webhook_endpoint
          render_webhook_endpoint(webhook_endpoint)
        else
          not_found_error(resource: "webhook_endpoint")
        end
      end

      def create
        input = input_params
        return invalid_signature_algo_error unless valid_signature_algo?(input)

        result = ::WebhookEndpoints::CreateService.call(organization: current_organization, params: input)

        if result.success?
          render_webhook_endpoint(result.webhook_endpoint)
        else
          render_error_response(result)
        end
      end

      def update
        input = input_params
        return invalid_signature_algo_error unless valid_signature_algo?(input)

        result = ::WebhookEndpoints::UpdateService.call(id: params[:id], organization: current_organization, params: input)

        if result.success?
          render_webhook_endpoint(result.webhook_endpoint)
        else
          render_error_response(result)
        end
      end

      def destroy
        result = ::WebhookEndpoints::DestroyService.call(webhook_endpoint: find_webhook_endpoint)

        if result.success?
          render_webhook_endpoint(result.webhook_endpoint)
        else
          render_error_response(result)
        end
      end

      private

      def find_webhook_endpoint
        current_organization.webhook_endpoints.find_by(id: params[:id])
      end

      def input_params
        raw_input = params.require(:webhook_endpoint)
        raise ActionController::ParameterMissing, :webhook_endpoint unless raw_input.is_a?(ActionController::Parameters)

        input = raw_input.permit(:webhook_url, :signature_algo, :name, event_types: [])

        # A scalar event_types is dropped by permit: the model refuses it rather than ignoring it.
        input[:event_types] = raw_input[:event_types] if raw_input.key?(:event_types) && !input.key?(:event_types)
        input
      end

      # The services cast it to an enum value, which raises on an unknown one.
      def valid_signature_algo?(input)
        !input.key?(:signature_algo) || WebhookEndpoint.signature_algos.key?(input[:signature_algo])
      end

      def invalid_signature_algo_error
        validation_errors(
          errors: {signature_algo: ["value_is_invalid"]},
          meta: {signature_algo: {allowed_values: WebhookEndpoint.signature_algos.keys}}
        )
      end

      def resource_name
        "webhook_endpoint"
      end
    end
  end
end
