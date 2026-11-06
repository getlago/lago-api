# frozen_string_literal: true

module Api
  module V2
    class WebhookEndpointsController < Api::V2::BaseController
      cursor_paginated_index(WebhookEndpoint)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::WebhookEndpointSerializer, expand_on: %i[show create update]

      # The create and update responses carry the whsec_ signing keys on expands[]=signing_keys.
      filter_audit_log_response! :secret_key

      # Declared after validate_expand!, so an unknown expansion stays a 400 before this 403.
      before_action :forbid_signing_keys_to_read_only_key, only: :show

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
        result = ::WebhookEndpoints::CreateService.call(
          organization: current_organization,
          params: input_params,
          signature_algo_rule: WebhookEndpoint::V2_SIGNATURE_ALGO_RULE
        )

        if result.success?
          render_webhook_endpoint(result.webhook_endpoint)
        else
          render_error_response(result)
        end
      end

      def update
        result = ::WebhookEndpoints::UpdateService.call(
          id: params[:id],
          organization: current_organization,
          params: input_params,
          signature_algo_rule: WebhookEndpoint::V2_SIGNATURE_ALGO_RULE
        )

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

      # authorize lets a read-only key through on GET, but only a key that can write webhook
      # endpoints reads their signing secrets, as in v1.
      def forbid_signing_keys_to_read_only_key
        if requested_expansions.include?(:signing_keys) && !current_api_key.permit?(resource_name, "write")
          forbidden_error(code: "write_action_not_allowed_for_#{resource_name}")
        end
      end

      def input_params
        raw_input = params.require(:webhook_endpoint)
        raise ActionController::ParameterMissing, :webhook_endpoint unless raw_input.is_a?(ActionController::Parameters)

        input = raw_input.permit(:webhook_url, :signature_algo, :name, event_types: [])

        # A scalar event_types is dropped by permit: the model refuses it rather than ignoring it.
        input[:event_types] = raw_input[:event_types] if raw_input.key?(:event_types) && !input.key?(:event_types)
        input
      end

      def resource_name
        "webhook_endpoint"
      end
    end
  end
end
