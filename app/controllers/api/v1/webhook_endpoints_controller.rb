# frozen_string_literal: true

module Api
  module V1
    class WebhookEndpointsController < Api::BaseController
      def create
        service = ::WebhookEndpoints::CreateService.new(
          organization: current_organization,
          params: create_params
        )

        result = service.call

        return render_webhook_endpoint(result.webhook_endpoint) if result.success?

        render_error_response(result)
      end

      def update
        service = ::WebhookEndpoints::UpdateService.new(
          id: params[:id],
          organization: current_organization,
          params: update_params
        )

        result = service.call

        return render_webhook_endpoint(result.webhook_endpoint) if result.success?

        render_error_response(result)
      end

      def index
        result = WebhookEndpointsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.webhook_endpoints,
              ::V1::WebhookEndpointSerializer,
              collection_name: "webhook_endpoints",
              meta: pagination_metadata(result.webhook_endpoints)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        webhook_endpoint = current_organization.webhook_endpoints.find_by(id: params[:id])

        return not_found_error(resource: "webhook_endpoint") unless webhook_endpoint

        render_webhook_endpoint(webhook_endpoint)
      end

      def destroy
        webhook_endpoint = current_organization.webhook_endpoints.find_by(id: params[:id])
        result = ::WebhookEndpoints::DestroyService.call(webhook_endpoint:)

        if result.success?
          render_webhook_endpoint(result.webhook_endpoint)
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:webhook_endpoint).permit(
          :id,
          :webhook_url,
          :signature_algo
        )
      end

      def update_params
        params.require(:webhook_endpoint).permit(
          :webhook_url,
          :signature_algo
        )
      end

      def render_webhook_endpoint(webhook_endpoint)
        render(
          json: ::V1::WebhookEndpointSerializer.new(
            webhook_endpoint,
            root_name: "webhook_endpoint"
          )
        )
      end

      def resource_name
        "webhook_endpoint"
      end
    end
  end
end
