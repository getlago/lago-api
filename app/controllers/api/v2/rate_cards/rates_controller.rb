# frozen_string_literal: true

module Api
  module V2
    module RateCards
      class RatesController < Api::BaseController
        before_action :find_rate_card
        before_action :find_rate, only: %i[show update destroy]

        def index
          rates = rate_card.rates
            .page(params[:page])
            .per(params[:per_page] || PER_PAGE)

          render(
            json: ::CollectionSerializer.new(
              rates,
              ::V1::RateCardRateSerializer,
              collection_name: "rates",
              meta: pagination_metadata(rates)
            )
          )
        end

        def show
          render_rate(rate)
        end

        def create
          result = ::RateCardRates::CreateService.call(
            rate_card:,
            params: input_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_rate(result.rate_card_rate)
          else
            render_error_response(result)
          end
        end

        def update
          result = ::RateCardRates::UpdateService.call(
            rate_card_rate: rate,
            params: input_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_rate(result.rate_card_rate)
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::RateCardRates::DestroyService.call(rate_card_rate: rate)

          if result.success?
            render_rate(result.rate_card_rate)
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :rate_card, :rate

        def find_rate_card
          @rate_card = current_organization.rate_cards.find_by(code: params[:rate_card_code])

          not_found_error(resource: "rate_card") unless rate_card
        end

        def find_rate
          @rate = rate_card.rates.find_by(id: params[:id])

          not_found_error(resource: "rate_card_rate") unless rate
        end

        def input_params
          params.require(:rate).permit(
            :effective_datetime,
            :rate_model,
            :min_amount_cents,
            :billing_interval_count,
            :billing_interval_unit,
            :applied_pricing_unit_conversion_rate,
            rate_properties: {}
          )
        end

        def render_rate(rate)
          render(json: ::V1::RateCardRateSerializer.new(rate, root_name: "rate"))
        end

        def resource_name
          "rate_card"
        end
      end
    end
  end
end
