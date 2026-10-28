# frozen_string_literal: true

module Api
  module V2
    class TaxesController < Api::V2::BaseController
      cursor_paginated_index(Tax)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::TaxSerializer

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
        result = ::TaxesQuery.call(organization: current_organization, pagination: cursor, filters: date_range_filters)

        if result.success?
          render_taxes(result.taxes)
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:tax).permit(:code, :description, :name, :rate)
      end

      def resource_name
        "tax"
      end
    end
  end
end
