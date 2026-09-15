# frozen_string_literal: true

module Api
  module V2
    class PlansController < Api::BaseController
      include Api::RequiresProductCatalog

      def index
        result = CatalogPlansQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.catalog_plans,
              ::V2::CatalogPlanSerializer,
              collection_name: "plans",
              meta: pagination_metadata(result.catalog_plans)
            )
          )
        else
          render_error_response(result)
        end
      end

      def create
        result = ::CatalogPlans::CreateService.call(input_params.merge(organization_id: current_organization.id).to_h.deep_symbolize_keys)

        if result.success?
          render_plan(result.catalog_plan)
        else
          render_error_response(result)
        end
      end

      def update
        catalog_plan = current_organization.catalog_plans.find_by(code: params[:code])
        result = ::CatalogPlans::UpdateService.call(catalog_plan:, params: input_params.to_h.deep_symbolize_keys)

        if result.success?
          render_plan(result.catalog_plan)
        else
          render_error_response(result)
        end
      end

      def show
        catalog_plan = current_organization.catalog_plans.find_by(code: params[:code])
        return not_found_error(resource: "plan") unless catalog_plan

        render_plan(catalog_plan)
      end

      private

      def input_params
        params.require(:plan).permit(:name, :code, :description, :invoice_display_name, :currency)
      end

      def render_plan(catalog_plan)
        render(json: ::V2::CatalogPlanSerializer.new(catalog_plan, root_name: "plan"))
      end

      def resource_name
        "plan"
      end
    end
  end
end
