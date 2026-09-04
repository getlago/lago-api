# frozen_string_literal: true

module Api
  module V2
    class ContractRateCardsController < Api::BaseController
      include Api::RequiresProductCatalog

      def create
        return not_found_error(resource: "contract") unless find_contract

        result = ::ContractRateCards::CreateService.call(
          contract: find_contract,
          params: create_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_contract_rate_card(result.contract_rate_card)
        else
          render_error_response(result)
        end
      end

      def show
        contract_rate_card = find_contract_rate_card

        return not_found_error(resource: "applied_rate_card") unless contract_rate_card

        render_contract_rate_card(contract_rate_card)
      end

      def update
        contract_rate_card = find_contract_rate_card
        result = ::ContractRateCards::UpdateService.call(
          contract_rate_card:,
          params: update_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_contract_rate_card(result.contract_rate_card)
        else
          render_error_response(result)
        end
      end

      def destroy
        contract_rate_card = find_contract_rate_card
        result = ::ContractRateCards::DestroyService.call(contract_rate_card:)

        if result.success?
          render_contract_rate_card(result.contract_rate_card)
        else
          render_error_response(result)
        end
      end

      def index
        return not_found_error(resource: "contract") unless find_contract

        result = ::ContractRateCardsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {contract_id: find_contract.id}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.contract_rate_cards.includes(:contract, :rate_card, :rate_phases),
              ::V2::ContractAppliedRateCardSerializer,
              collection_name: "applied_rate_cards",
              meta: pagination_metadata(result.contract_rate_cards)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def find_contract
        @find_contract ||= current_organization.contracts.live_by_external_id(params[:contract_external_id])
      end

      def find_contract_rate_card
        contract = find_contract
        return nil unless contract

        contract.applied_rate_cards.current_and_scheduled.joins(:rate_card).find_by(rate_cards: {code: params[:code]})
      end

      def create_params
        params.require(:applied_rate_card).permit(
          :rate_card_code, :units, :billing_anchor_date,
          rate_phases: [
            :code,
            :position,
            :name,
            :billing_interval_cycle_count,
            {rate_override: [
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
            ]}
          ]
        )
      end

      def update_params
        params.require(:applied_rate_card).permit(:units, :billing_anchor_date)
      end

      def render_contract_rate_card(contract_rate_card)
        render(json: ::V2::ContractAppliedRateCardSerializer.new(contract_rate_card, root_name: "applied_rate_card"))
      end

      def resource_name
        "contract_rate_card"
      end
    end
  end
end
