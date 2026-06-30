# frozen_string_literal: true

module Api
  module V2
    class PlanRateCardsController < Api::BaseController
      def create
        result = ::PlanRateCards::CreateService.call(
          plan: find_plan,
          params: create_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_plan_rate_card(result.plan_rate_card)
        else
          render_error_response(result)
        end
      end

      def show
        plan_rate_card = find_plan_rate_card

        return not_found_error(resource: "plan_rate_card") unless plan_rate_card

        render_plan_rate_card(plan_rate_card)
      end

      def update
        plan_rate_card = find_plan_rate_card
        result = ::PlanRateCards::UpdateService.call(
          plan_rate_card:,
          params: update_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_plan_rate_card(result.plan_rate_card)
        else
          render_error_response(result)
        end
      end

      def destroy
        plan_rate_card = find_plan_rate_card
        result = ::PlanRateCards::DestroyService.call(plan_rate_card:)

        if result.success?
          render_plan_rate_card(result.plan_rate_card)
        else
          render_error_response(result)
        end
      end

      def index
        return not_found_error(resource: "plan") unless find_plan

        result = ::PlanRateCardsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {plan_code: params[:plan_code]}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.plan_rate_cards,
              ::V1::PlanRateCardSerializer,
              collection_name: "plan_rate_cards",
              meta: pagination_metadata(result.plan_rate_cards)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      # All routes are nested under the plan: an entry is addressed by its
      # natural key — the plan code and the rate card code (unique together
      # thanks to the one-card-per-slice rule) — so consumers never have to
      # persist Lago-generated ids.
      def find_plan
        current_organization.plans.parents.find_by(code: params[:plan_code])
      end

      def find_plan_rate_card
        plan = find_plan
        return nil unless plan

        plan.plan_rate_cards.joins(:rate_card).find_by(rate_cards: {code: params[:code]})
      end

      def create_params
        params.require(:plan_rate_card).permit(:rate_card_code, :units)
      end

      def update_params
        params.require(:plan_rate_card).permit(:units)
      end

      def render_plan_rate_card(plan_rate_card)
        render(json: ::V1::PlanRateCardSerializer.new(plan_rate_card, root_name: "plan_rate_card"))
      end

      def resource_name
        "plan_rate_card"
      end
    end
  end
end
