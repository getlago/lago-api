# frozen_string_literal: true

module Api
  module V2
    module Products
      class FiltersController < Api::BaseController
        include Api::RequiresProductCatalog

        before_action :find_product
        before_action :find_product_filter, only: %i[show update destroy]

        def index
          result = ::ProductFiltersQuery.call(
            organization: current_organization,
            search_term: params[:search_term],
            pagination: {
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            },
            filters: {product_id: product.id}
          )

          if result.success?
            render(
              json: ::CollectionSerializer.new(
                result.product_filters,
                ::V1::ProductFilterSerializer,
                collection_name: "filters",
                meta: pagination_metadata(result.product_filters)
              )
            )
          else
            render_error_response(result)
          end
        end

        def show
          render_filter(product_filter)
        end

        def create
          result = ::ProductFilters::CreateService.call(
            product:,
            params: input_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_filter(result.product_filter)
          else
            render_error_response(result)
          end
        end

        def update
          result = ::ProductFilters::UpdateService.call(
            product_filter:,
            params: update_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_filter(result.product_filter)
          else
            render_error_response(result)
          end
        end

        def destroy
          values = product_filter.values.to_a
          result = ::ProductFilters::DestroyService.call(product_filter:)

          if result.success?
            render_filter(result.product_filter, values:)
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :product, :product_filter

        def find_product
          @product = current_organization.products.find_by(code: params[:product_code])

          not_found_error(resource: "product") unless product
        end

        def find_product_filter
          @product_filter = product.filters.find_by(code: params[:code])

          not_found_error(resource: "product_filter") unless product_filter
        end

        def input_params
          params.require(:filter).permit(
            :name,
            :code,
            :description,
            :invoice_display_name,
            values: %i[key value]
          )
        end

        def update_params
          params.require(:filter).permit(
            :name,
            :code,
            :description,
            :invoice_display_name,
            values: %i[key value]
          )
        end

        def render_filter(filter, values: nil)
          render(json: ::V1::ProductFilterSerializer.new(filter, root_name: "filter", values:))
        end

        def resource_name
          "product"
        end
      end
    end
  end
end
