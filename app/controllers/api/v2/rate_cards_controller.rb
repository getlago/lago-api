# frozen_string_literal: true

module Api
  module V2
    class RateCardsController < Api::BaseController
      def create
        if create_params.key?(:product_item_filter_code) && product_item && product_item_filter.nil?
          return not_found_error(resource: "product_item_filter")
        end

        result = ::RateCards::CreateService.call(
          product_item:,
          params: create_params
            .except(:product_item_code, :product_item_filter_code)
            .to_h.deep_symbolize_keys
            .merge(product_item_filter_id: product_item_filter&.id)
        )

        if result.success?
          render_rate_card(result.rate_card)
        else
          render_error_response(result)
        end
      end

      def update
        rate_card = current_organization.rate_cards.find_by(code: params[:code])
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
        rate_card = current_organization.rate_cards.find_by(code: params[:code])
        result = ::RateCards::DestroyService.call(rate_card:)

        if result.success?
          render_rate_card(result.rate_card)
        else
          render_error_response(result)
        end
      end

      def show
        rate_card = current_organization.rate_cards.find_by(code: params[:code])

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
            product_item_id: params[:product_item_id],
            product_item_filter_id: params[:product_item_filter_id]
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.rate_cards,
              ::V1::RateCardSerializer,
              collection_name: "rate_cards",
              meta: pagination_metadata(result.rate_cards)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def product_item
        @product_item ||= current_organization.product_items.find_by(code: create_params[:product_item_code])
      end

      def product_item_filter
        return nil unless product_item && create_params[:product_item_filter_code]

        @product_item_filter ||= product_item.filters.find_by(code: create_params[:product_item_filter_code])
      end

      def create_params
        params.require(:rate_card).permit(
          :product_item_code,
          :product_item_filter_code,
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
          rates: [
            :effective_datetime,
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
          :description,
          :currency,
          :billing_timing,
          :proration,
          :display_on_invoice,
          :regroup_paid_fees,
          :applied_pricing_unit_code,
          :wallet_targetable
        )
      end

      def render_rate_card(rate_card)
        render(json: ::V1::RateCardSerializer.new(rate_card, root_name: "rate_card", includes: %i[rates]))
      end

      def resource_name
        "rate_card"
      end
    end
  end
end
