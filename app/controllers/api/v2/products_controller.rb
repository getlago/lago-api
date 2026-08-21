# frozen_string_literal: true

module Api
  module V2
    class ProductsController < Api::BaseController
      include Api::RequiresProductCatalog

      ERROR_FIELDS = {billable_metric: :billable_metric_code, product_category: :product_category_code}.freeze

      def create
        if input_params[:product_category_code].present? && product_category.nil?
          return not_found_error(resource: "product_category")
        end

        if input_params.key?(:billable_metric_code) && billable_metric.nil?
          return not_found_error(resource: "billable_metric")
        end

        result = ::Products::CreateService.call(
          organization: current_organization,
          params: input_params
            .except(:product_category_code, :billable_metric_code)
            .to_h.symbolize_keys
            .merge(product_category_id: product_category&.id, billable_metric_id: billable_metric&.id)
        )

        if result.success?
          render_product(result.product)
        else
          render_item_error(result)
        end
      end

      def update
        product = current_organization.products.find_by(code: params[:code])

        if update_params[:product_category_code].present? && updated_product_category.nil?
          return not_found_error(resource: "product_category")
        end

        service_params = update_params.except(:product_category_code).to_h.symbolize_keys
        # A blank code detaches the product from its product_category.
        if update_params.key?(:product_category_code)
          service_params[:product_category_id] = updated_product_category&.id
        end

        result = ::Products::UpdateService.call(product:, params: service_params)

        if result.success?
          render_product(result.product)
        else
          render_item_error(result)
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
        if index_product_category_codes.present? && index_product_categories.size != index_product_category_codes.size
          return not_found_error(resource: "product_category")
        end

        # The column is a PG enum: an unknown value would fail the SQL cast.
        if params[:product_type].present? && !Product::PRODUCT_TYPES.value?(params[:product_type])
          return validation_errors(errors: {product_type: ["value_is_invalid"]})
        end

        result = ::ProductsQuery.call(
          organization: current_organization,
          search_term: params[:search_term],
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {
            product_category_ids: index_product_categories.map(&:id).presence,
            without_product_category: ActiveModel::Type::Boolean.new.cast(params[:without_product_category]),
            product_type: params[:product_type]
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              # Preloaded so filters_count reads the loaded association.
              result.products.includes(:filters),
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

      def product_category
        @product_category ||= current_organization.product_categories.find_by(code: input_params[:product_category_code])
      end

      def billable_metric
        @billable_metric ||= current_organization.billable_metrics.find_by(code: input_params[:billable_metric_code])
      end

      def index_product_category_codes
        @index_product_category_codes ||= Array(params[:product_category_code]).compact_blank
      end

      def index_product_categories
        @index_product_categories ||= current_organization.product_categories.where(code: index_product_category_codes).to_a
      end

      def updated_product_category
        @updated_product_category ||= current_organization.product_categories.find_by(code: update_params[:product_category_code])
      end

      def input_params
        params.require(:product).permit(
          :name,
          :code,
          :description,
          :invoice_display_name,
          :product_type,
          :product_category_code,
          :billable_metric_code
        )
      end

      def update_params
        params.require(:product).permit(
          :name,
          :code,
          :description,
          :invoice_display_name,
          :product_category_code
        )
      end

      def render_product(product)
        render(json: ::V1::ProductSerializer.new(product, root_name: "product"))
      end

      def render_item_error(result)
        if result.error.is_a?(BaseService::ValidationFailure)
          messages = result.error.messages.transform_keys { |key| ERROR_FIELDS[key.to_sym] || key }
          return validation_errors(errors: messages)
        end

        render_error_response(result)
      end

      def resource_name
        "product"
      end
    end
  end
end
