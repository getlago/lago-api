# frozen_string_literal: true

module Api
  module V1
    class TaxesController < Api::BaseController
      def create
        result = Taxes::CreateService.call(organization: current_organization, params: input_params)

        if result.success?
          render_tax(result.tax)
        else
          render_error_response(result)
        end
      end

      def update
        tax = current_organization.taxes.find_by(code: params[:code])
        result = Taxes::UpdateService.call(tax:, params: input_params)

        if result.success?
          render_tax(result.tax)
        else
          render_error_response(result)
        end
      end

      def destroy
        tax = current_organization.taxes.find_by(code: params[:code])
        result = Taxes::DestroyService.call(tax:)

        if result.success?
          render_tax(result.tax)
        else
          render_error_response(result)
        end
      end

      def show
        tax = current_organization.taxes.find_by(code: params[:code])
        return not_found_error(resource: 'tax') unless tax

        render_tax(tax)
      end

      def index
        taxes = current_organization.taxes
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            taxes,
            ::V1::TaxSerializer,
            collection_name: 'taxes',
            meta: pagination_metadata(taxes),
          ),
        )
      end

      private

      def input_params
        params.require(:tax).permit(:code, :description, :name, :rate, :applied_to_organization)
      end

      def render_tax(tax)
        render(json: ::V1::TaxSerializer.new(tax, root_name: 'tax'))
      end
    end
  end
end
