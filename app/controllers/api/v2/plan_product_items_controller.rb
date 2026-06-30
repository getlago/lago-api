# frozen_string_literal: true

module Api
  module V2
    class PlanProductItemsController < Api::BaseController
      def create
        plan = current_organization.plans.find_by(id: create_params[:plan_id])
        result = ::PlanProductItems::CreateService.call(
          plan:,
          params: create_params.except(:plan_id).to_h.deep_symbolize_keys
        )

        if result.success?
          render_plan_product_item(result.plan_product_item)
        else
          render_error_response(result)
        end
      end

      def show
        plan_product_item = plan_product_items_scope.find_by(id: params[:id])

        return not_found_error(resource: "plan_product_item") unless plan_product_item

        render_plan_product_item(plan_product_item)
      end

      def index
        result = ::PlanProductItemsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {plan_id: params[:plan_id]}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.plan_product_items,
              ::V1::PlanProductItemSerializer,
              collection_name: "plan_product_items",
              meta: pagination_metadata(result.plan_product_items)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def plan_product_items_scope
        PlanProductItem.where(organization: current_organization)
      end

      def create_params
        params.require(:plan_product_item).permit(:plan_id, :product_item_id, :rate_card_id, :units)
      end

      def render_plan_product_item(plan_product_item)
        render(json: ::V1::PlanProductItemSerializer.new(plan_product_item, root_name: "plan_product_item"))
      end

      def resource_name
        "plan_product_item"
      end
    end
  end
end
