# frozen_string_literal: true

module Api
  module V1
    class ProductItemsController < Api::BaseController
      def create
        result = ::ProductItems::CreateService.call(
          organization: current_organization,
          params: input_params.to_h.symbolize_keys
        )

        if result.success?
          render_product_item(result.product_item)
        else
          render_error_response(result)
        end
      end

      def update
        product_item = current_organization.product_items.find_by(id: params[:id])
        result = ::ProductItems::UpdateService.call(product_item:, params: update_params.to_h.symbolize_keys)

        if result.success?
          render_product_item(result.product_item)
        else
          render_error_response(result)
        end
      end

      def destroy
        product_item = current_organization.product_items.find_by(id: params[:id])
        result = ::ProductItems::DestroyService.call(product_item:)

        if result.success?
          render_product_item(result.product_item)
        else
          render_error_response(result)
        end
      end

      def show
        product_item = current_organization.product_items.find_by(id: params[:id])

        return not_found_error(resource: "product_item") unless product_item

        render_product_item(product_item)
      end

      def index
        result = ::ProductItemsQuery.call(
          organization: current_organization,
          search_term: params[:search_term],
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {
            product_id: params[:product_id],
            item_type: params[:item_type]
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.product_items,
              ::V1::ProductItemSerializer,
              collection_name: "product_items",
              meta: pagination_metadata(result.product_items)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:product_item).permit(
          :name,
          :code,
          :description,
          :invoice_display_name,
          :item_type,
          :product_id,
          :billable_metric_id
        )
      end

      def update_params
        params.require(:product_item).permit(
          :name,
          :code,
          :description,
          :invoice_display_name,
          :product_id
        )
      end

      def render_product_item(product_item)
        render(json: ::V1::ProductItemSerializer.new(product_item, root_name: "product_item"))
      end

      def resource_name
        "product_item"
      end
    end
  end
end
