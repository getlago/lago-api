# frozen_string_literal: true

module Api
  module V2
    class RateCardsController < Api::BaseController
      include Api::RequiresProductCatalog

      def create
        if create_params[:product_filter_code].present? && product && product_filter.nil?
          return not_found_error(resource: "product_filter")
        end

        result = ::RateCards::CreateService.call(
          product:,
          params: create_params
            .except(:product_code, :product_filter_code)
            .to_h.deep_symbolize_keys
            .merge(product_filter_id: product_filter&.id)
        )

        if result.success?
          render_rate_card(result.rate_card)
        else
          render_error_response(result)
        end
      end

      def update
        result = ::RateCards::UpdateService.call(
          rate_card:,
          params: update_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_rate_card(result.rate_card)
        else
          render_error_response(result)
        end
      end

      def destroy
        result = ::RateCards::DestroyService.call(rate_card:)

        if result.success?
          render_rate_card(result.rate_card)
        else
          render_error_response(result)
        end
      end

      def show
        return not_found_error(resource: "rate_card") unless rate_card

        render_rate_card(rate_card)
      end

      def index
        result = ::RateCardsQuery.call(
          organization: current_organization,
          search_term: params[:search_term],
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {
            product_id: params[:product_id],
            product_filter_id: params[:product_filter_id],
            code: params[:code],
            product_code: params[:product_code],
            product_filter_code: params[:product_filter_code]
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.rate_cards.includes(:product, :product_filter, :rates, :taxes),
              ::V1::RateCardSerializer,
              collection_name: "rate_cards",
              meta: pagination_metadata(result.rate_cards),
              includes: %i[taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def rate_card
        @rate_card ||= current_organization.rate_cards.find_by(code: params[:code])
      end

      def product
        @product ||= current_organization.products.find_by(code: create_params[:product_code])
      end

      def product_filter
        return nil unless product && create_params[:product_filter_code].present?

        @product_filter ||= product.filters.find_by(code: create_params[:product_filter_code])
      end

      def create_params
        params.require(:rate_card).permit(
          :product_code,
          :product_filter_code,
          :name,
          :code,
          :description,
          :currency,
          :billing_timing,
          :proration,
          :display_on_invoice,
          :regroup_paid_fees,
          :applied_pricing_unit_code,
          :wallet_targetable,
          tax_codes: [],
          rates: [
            :code,
            :effective_from,
            :rate_model,
            :min_amount_cents,
            :billing_interval_count,
            :billing_interval_unit,
            :applied_pricing_unit_conversion_rate,
            {rate_properties: {}}
          ]
        )
      end

      def update_params
        params.require(:rate_card).permit(
          :name,
          :code,
          :description,
          :currency,
          :billing_timing,
          :proration,
          :display_on_invoice,
          :regroup_paid_fees,
          :applied_pricing_unit_code,
          :wallet_targetable,
          tax_codes: []
        )
      end

      def render_rate_card(rate_card)
        render(json: ::V1::RateCardSerializer.new(rate_card, root_name: "rate_card", includes: %i[active_rate taxes]))
      end

      def resource_name
        "rate_card"
      end
    end
  end
end
