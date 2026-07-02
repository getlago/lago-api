# frozen_string_literal: true

module Api
  module V2
    module PlanProductItems
      class RatePhasesController < Api::BaseController
        def index
          return not_found_error(resource: "plan_product_item") unless plan_product_item

          render_rate_phases(plan_product_item.rate_phases.order(:position))
        end

        def replace
          return not_found_error(resource: "plan_product_item") unless plan_product_item

          result = ::RatePhases::ReplaceService.call(
            plan_product_item:,
            phases_params: replace_params
          )

          if result.success?
            render_rate_phases(result.rate_phases)
          else
            render_error_response(result)
          end
        end

        private

        def plan_product_item
          @plan_product_item ||= PlanProductItem
            .where(organization: current_organization)
            .find_by(id: params[:plan_product_item_id])
        end

        def replace_params
          params
            .permit(rate_phases: %i[position name billing_interval_cycle_count])
            .to_h
            .deep_symbolize_keys
            .fetch(:rate_phases, [])
        end

        def render_rate_phases(rate_phases)
          render(
            json: ::CollectionSerializer.new(
              rate_phases,
              ::V1::RatePhaseSerializer,
              collection_name: "rate_phases"
            )
          )
        end

        def resource_name
          "plan_product_item"
        end
      end
    end
  end
end
