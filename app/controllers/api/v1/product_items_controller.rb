# frozen_string_literal: true

module Api
  module V1
    class ProductItemsController < Api::BaseController
      def create
        if input_params.key?(:product_code) && product.nil?
          return not_found_error(resource: "product")
        end

        if input_params.key?(:billable_metric_code) && billable_metric.nil?
          return not_found_error(resource: "billable_metric")
        end

        result = ::ProductItems::CreateService.call(
          organization: current_organization,
          params: input_params
            .except(:product_code, :billable_metric_code)
            .to_h.symbolize_keys
            .merge(product_id: product&.id, billable_metric_id: billable_metric&.id)
        )

        if result.success?
          render_product_item(result.product_item)
        else
          render_item_error(result)
        end
      end

      def update
        product_item = current_organization.product_items.find_by(code: params[:code])

        if update_params.key?(:product_code) && updated_product.nil?
          return not_found_error(resource: "product")
        end

        service_params = update_params.except(:product_code).to_h.symbolize_keys
        if update_params.key?(:product_code)
          service_params[:product_id] = updated_product.id
        end

        result = ::ProductItems::UpdateService.call(product_item:, params: service_params)

        if result.success?
          render_product_item(result.product_item)
        else
          render_item_error(result)
        end
      end

      def destroy
        product_item = current_organization.product_items.find_by(code: params[:code])
        result = ::ProductItems::DestroyService.call(product_item:)

        if result.success?
          render_product_item(result.product_item)
        else
          render_error_response(result)
        end
      end

      def show
        product_item = current_organization.product_items.find_by(code: params[:code])

        return not_found_error(resource: "product_item") unless product_item

        render_product_item(product_item)
      end

      def index
        if index_product_codes.present? && index_products.size != index_product_codes.size
          return not_found_error(resource: "product")
        end

        result = ::ProductItemsQuery.call(
          organization: current_organization,
          search_term: params[:search_term],
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {
            product_ids: index_products.map(&:id).presence,
            without_product: ActiveModel::Type::Boolean.new.cast(params[:without_product]),
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

      def product
        @product ||= current_organization.products.find_by(code: input_params[:product_code])
      end

      def billable_metric
        @billable_metric ||= current_organization.billable_metrics.find_by(code: input_params[:billable_metric_code])
      end

      def index_product_codes
        @index_product_codes ||= Array(params[:product_code]).compact_blank
      end

      def index_products
        @index_products ||= current_organization.products.where(code: index_product_codes).to_a
      end

      def updated_product
        @updated_product ||= current_organization.products.find_by(code: update_params[:product_code])
      end

      def input_params
        params.require(:product_item).permit(
          :name,
          :code,
          :description,
          :invoice_display_name,
          :item_type,
          :product_code,
          :billable_metric_code
        )
      end

      def update_params
        params.require(:product_item).permit(
          :name,
          :code,
          :description,
          :invoice_display_name,
          :product_code
        )
      end

      def render_product_item(product_item)
        render(json: ::V1::ProductItemSerializer.new(product_item, root_name: "product_item"))
      end

      # billable_metric and product are supplied by code on the REST API, so a
      # validation error about either must name the code field the caller sent,
      # not the neutral association name the shared service/model emits.
      REST_ERROR_FIELDS = {billable_metric: :billable_metric_code, product: :product_code}.freeze

      def render_item_error(result)
        if result.error.is_a?(BaseService::ValidationFailure)
          messages = result.error.messages.transform_keys { |key| REST_ERROR_FIELDS[key.to_sym] || key }
          return validation_errors(errors: messages)
        end

        render_error_response(result)
      end

      def resource_name
        "product_item"
      end
    end
  end
end
