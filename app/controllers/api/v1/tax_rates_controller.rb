# frozen_string_literal: true

module Api
  module V1
    class TaxRatesController < Api::BaseController
      def create
        result = TaxRates::CreateService.call(organization: current_organization, params: input_params)

        if result.success?
          render_tax_rate(result.tax_rate)
        else
          render_error_response(result)
        end
      end

      def update
        tax_rate = current_organization.tax_rates.find_by(code: params[:code])
        result = TaxRates::UpdateService.call(tax_rate:, params: input_params)

        if result.success?
          render_tax_rate(result.tax_rate)
        else
          render_error_response(result)
        end
      end

      def destroy
        tax_rate = current_organization.tax_rates.find_by(code: params[:code])
        result = TaxRates::DestroyService.call(tax_rate:)

        if result.success?
          render_tax_rate(result.tax_rate)
        else
          render_error_response(result)
        end
      end

      def show
        tax_rate = current_organization.tax_rates.find_by(code: params[:code])
        return not_found_error(resource: 'tax_rate') unless tax_rate

        render_tax_rate(tax_rate)
      end

      def index
        tax_rates = current_organization.tax_rates
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            tax_rates,
            ::V1::TaxRateSerializer,
            collection_name: 'tax_rates',
            meta: pagination_metadata(tax_rates),
          ),
        )
      end

      private

      def input_params
        params.require(:tax_rate).permit(:code, :description, :name, :value)
      end

      def render_tax_rate(tax_rate)
        render(json: ::V1::TaxRateSerializer.new(tax_rate, root_name: 'tax_rate'))
      end
    end
  end
end
