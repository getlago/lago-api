# frozen_string_literal: true

module Api
  module V1
    class AgentStorefrontsController < Api::BaseController
      before_action :ensure_agent_storefront_enabled

      def create
        result = ::Integrations::AgentStorefront::CreateService.call(
          params: input_params.to_h.symbolize_keys.merge(organization_id: current_organization.id)
        )

        if result.success?
          render_storefront(result.integration)
        else
          render_error_response(result)
        end
      end

      def update
        storefront = find_storefront
        return not_found_error(resource: "agent_storefront") unless storefront

        result = ::Integrations::AgentStorefront::UpdateService.call(
          integration: storefront,
          params: input_params.to_h.symbolize_keys
        )

        if result.success?
          render_storefront(result.integration)
        else
          render_error_response(result)
        end
      end

      def destroy
        storefront = find_storefront
        return not_found_error(resource: "agent_storefront") unless storefront

        result = ::Integrations::DestroyService.call(integration: storefront)

        if result.success?
          render_storefront(result.integration)
        else
          render_error_response(result)
        end
      end

      def show
        storefront = find_storefront

        if storefront
          render_storefront(storefront)
        else
          not_found_error(resource: "agent_storefront")
        end
      end

      def index
        storefronts = current_organization.agent_storefront_integrations
          .order(created_at: :desc)
          .order(id: :asc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            storefronts,
            ::V1::AgentStorefrontSerializer,
            collection_name: "agent_storefronts",
            meta: pagination_metadata(storefronts)
          )
        )
      end

      private

      def ensure_agent_storefront_enabled
        forbidden_error(code: "feature_unavailable") unless current_organization.agent_storefront_enabled?
      end

      def find_storefront
        current_organization.agent_storefront_integrations.find_by(code: params[:code])
      end

      def input_params
        params.require(:agent_storefront).permit(
          :code,
          :name,
          :payment_provider_code,
          :resource_endpoint,
          :resource_instructions
        )
      end

      def render_storefront(storefront)
        render(json: ::V1::AgentStorefrontSerializer.new(storefront, root_name: "agent_storefront"))
      end

      def resource_name
        "agent_storefront"
      end
    end
  end
end
