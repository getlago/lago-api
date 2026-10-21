# frozen_string_literal: true

module Api
  module V2
    class TaxesController < Api::V2::BaseController
      # Expansion errors follow authorization and feature checks but precede cursor validation.
      skip_before_action :read_cursor
      before_action :validate_expand!
      before_action :read_cursor, if: :cursor_paginated_index?

      cursor_paginated_index(Tax)

      def create
        result = ::Taxes::CreateService.call(organization: current_organization, params: input_params)

        if result.success?
          render_tax(result.tax)
        else
          render_error_response(result)
        end
      end

      def update
        tax = current_organization.taxes.find_by(code: params[:code])
        result = ::Taxes::UpdateService.call(tax:, params: input_params)

        if result.success?
          render_tax(result.tax)
        else
          render_error_response(result)
        end
      end

      def destroy
        tax = current_organization.taxes.find_by(code: params[:code])
        result = ::Taxes::DestroyService.call(tax:)

        if result.success?
          render_tax(result.tax)
        else
          render_error_response(result)
        end
      end

      def show
        tax = current_organization.taxes.find_by(code: params[:code])

        if tax
          render_tax(tax)
        else
          not_found_error(resource: "tax")
        end
      end

      def index
        result = ::TaxesQuery.call(organization: current_organization, pagination: cursor)

        if result.success?
          page = ::CursorPagination::Page.new(records: result.taxes, cursor:)

          render(json: ::CollectionSerializer.new(
            page.records,
            ::V2::TaxSerializer,
            collection_name: "taxes",
            meta: page.meta,
            includes: [:deleted_at]
          ))
        else
          render_error_response(result)
        end
      end

      private

      def validate_expand!
        values = raw_expand_values

        if values.nil? || !values.all?(String)
          invalid_request_error(
            code: "invalid_expand",
            error_details: {expand: {reason: "malformed", allowed_values: []}}
          )
        else
          values = values.map(&:strip).compact_blank.uniq

          if values.any?
            invalid_request_error(
              code: "expand_not_supported",
              error_details: {expand: {reason: "not_expandable", invalid_values: values}}
            )
          end
        end
      end

      def raw_expand_values
        expand = params[:expand]

        case expand
        when nil then []
        when String then [expand]
        when Array then expand
        when ActionController::Parameters then expand.values if expand.keys.all?(/\A\d+\z/)
        end
      end

      def input_params
        params.require(:tax).permit(:code, :description, :name, :rate)
      end

      def render_tax(tax)
        render(json: ::V2::TaxSerializer.new(tax, root_name: "tax", includes: [:deleted_at]))
      end

      def resource_name
        "tax"
      end
    end
  end
end
