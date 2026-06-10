# frozen_string_literal: true

module Api
  module V1
    class ProductsController < Api::BaseController
      def create
        result = ::Products::CreateService.call(
          organization: current_organization,
          params: input_params.to_h.symbolize_keys
        )

        if result.success?
          render_product(result.product)
        else
          render_error_response(result)
        end
      end

      def update
        product = current_organization.products.find_by(code: params[:code])
        result = ::Products::UpdateService.call(product:, params: update_params.to_h.symbolize_keys)

        if result.success?
          render_product(result.product)
        else
          render_error_response(result)
        end
      end

      def destroy
        product = current_organization.products.find_by(code: params[:code])
        result = ::Products::DestroyService.call(product:)

        if result.success?
          render_product(result.product)
        else
          render_error_response(result)
        end
      end

      def show
        product = current_organization.products.find_by(code: params[:code])

        return not_found_error(resource: "product") unless product

        render_product(product)
      end

      def index
        result = ::ProductsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.products,
              ::V1::ProductSerializer,
              collection_name: "products",
              meta: pagination_metadata(result.products)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:product).permit(
          :name,
          :code,
          :description,
          :invoice_display_name
        )
      end

      def update_params
        params.require(:product).permit(
          :name,
          :description,
          :invoice_display_name
        )
      end

      def render_product(product)
        render(json: ::V1::ProductSerializer.new(product, root_name: "product"))
      end

      def resource_name
        "product"
      end
    end
  end
end
