# frozen_string_literal: true

module Api
  module V2
    module ContractRateCards
      class RatePhasesController < Api::BaseController
        include Api::RequiresProductCatalog

        def index
          return not_found_error(resource: "applied_rate_card") unless contract_rate_card

          render_rate_phases(contract_rate_card.rate_phases.includes(:rate_override).order(:position))
        end

        def create
          return not_found_error(resource: "applied_rate_card") unless contract_rate_card

          result = ::RatePhases::CreateService.call(
            contract_rate_card:,
            params: create_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_rate_phase(result.rate_phase)
          else
            render_error_response(result)
          end
        end

        def update
          rate_phase = find_rate_phase
          return not_found_error(resource: "rate_phase") unless rate_phase

          result = ::RatePhases::UpdateService.call(
            rate_phase:,
            params: update_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_rate_phase(result.rate_phase)
          else
            render_error_response(result)
          end
        end

        def destroy
          rate_phase = find_rate_phase
          return not_found_error(resource: "rate_phase") unless rate_phase

          result = ::RatePhases::DestroyService.call(rate_phase:)

          if result.success?
            render_rate_phase(result.rate_phase)
          else
            render_error_response(result)
          end
        end

        private

        def contract_rate_card
          @contract_rate_card ||= begin
            contract = current_organization.contracts.find_by(external_id: params[:contract_external_id])
            contract&.applied_rate_cards&.joins(:rate_card)&.find_by(rate_cards: {code: params[:applied_rate_card_code]})
          end
        end

        def find_rate_phase
          contract_rate_card&.rate_phases&.find_by(code: params[:code])
        end

        def create_params
          params.require(:rate_phase).permit(
            :code, :position, :name, :billing_interval_cycle_count,
            rate_override: [
              :rate_model,
              :min_amount_cents,
              :billing_interval_count,
              :billing_interval_unit,
              :pricing_unit_conversion_rate,
              # Structural card fields pass through so the override service can
              # reject them explicitly instead of strong params dropping them.
              :billing_timing,
              :currency,
              :proration,
              :display_on_invoice,
              :regroup_paid_fees,
              :wallet_targetable,
              :applied_pricing_unit_code,
              {rate_properties: {}}
            ]
          )
        end

        # Positions are not editable on update (ordering goes through insert
        # and delete), so update does not permit one.
        def update_params
          # Required before any wrapper inspection so a missing rate_phase key
          # stays a parameter-missing 400, not a NoMethodError.
          permitted = permitted_update_params

          # permit drops an explicit null; carry it through so an override can
          # be cleared over REST like it can over GraphQL.
          if params[:rate_phase].include?(:rate_override) && params[:rate_phase][:rate_override].nil?
            permitted = permitted.merge(rate_override: nil)
          end

          permitted
        end

        def permitted_update_params
          params.require(:rate_phase).permit(
            :code, :name, :billing_interval_cycle_count,
            rate_override: [
              :rate_model,
              :min_amount_cents,
              :billing_interval_count,
              :billing_interval_unit,
              :pricing_unit_conversion_rate,
              # Structural card fields pass through so the override service can
              # reject them explicitly instead of strong params dropping them.
              :billing_timing,
              :currency,
              :proration,
              :display_on_invoice,
              :regroup_paid_fees,
              :wallet_targetable,
              :applied_pricing_unit_code,
              {rate_properties: {}}
            ]
          )
        end

        def render_rate_phase(rate_phase)
          render(json: ::V2::RatePhaseSerializer.new(rate_phase, root_name: "rate_phase"))
        end

        def render_rate_phases(rate_phases)
          render(
            json: ::CollectionSerializer.new(
              rate_phases,
              ::V2::RatePhaseSerializer,
              collection_name: "rate_phases"
            )
          )
        end

        def resource_name
          "contract_rate_card"
        end
      end
    end
  end
end
