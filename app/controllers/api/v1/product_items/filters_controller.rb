# frozen_string_literal: true

module Api
  module V1
    module ProductItems
      class FiltersController < Api::BaseController
        before_action :find_product_item
        before_action :find_product_item_filter, only: %i[show update destroy]

        def index
          filters = product_item.filters
            .includes(values: :billable_metric_filter)
            .page(params[:page])
            .per(params[:per_page] || PER_PAGE)

          render(
            json: ::CollectionSerializer.new(
              filters,
              ::V1::ProductItemFilterSerializer,
              collection_name: "filters",
              meta: pagination_metadata(filters)
            )
          )
        end

        def show
          render_filter(product_item_filter)
        end

        def create
          result = ::ProductItemFilters::CreateService.call(
            product_item:,
            params: input_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_filter(result.product_item_filter)
          else
            render_error_response(result)
          end
        end

        def update
          result = ::ProductItemFilters::UpdateService.call(
            product_item_filter:,
            params: update_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_filter(result.product_item_filter)
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::ProductItemFilters::DestroyService.call(product_item_filter:)

          if result.success?
            render_filter(result.product_item_filter)
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :product_item, :product_item_filter

        def find_product_item
          @product_item = current_organization.product_items.find_by(id: params[:product_item_id])

          not_found_error(resource: "product_item") unless product_item
        end

        def find_product_item_filter
          @product_item_filter = product_item.filters.find_by(id: params[:id])

          not_found_error(resource: "product_item_filter") unless product_item_filter
        end

        def input_params
          params.require(:filter).permit(
            :name,
            :code,
            :description,
            :invoice_display_name,
            values: %i[billable_metric_filter_id value]
          )
        end

        def update_params
          params.require(:filter).permit(
            :name,
            :description,
            :invoice_display_name,
            values: %i[billable_metric_filter_id value]
          )
        end

        def render_filter(filter)
          render(json: ::V1::ProductItemFilterSerializer.new(filter, root_name: "filter"))
        end

        def resource_name
          "product_item"
        end
      end
    end
  end
end
