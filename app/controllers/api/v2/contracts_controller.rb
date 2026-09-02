# frozen_string_literal: true

module Api
  module V2
    class ContractsController < Api::BaseController
      include Api::RequiresProductCatalog

      def create
        result = ::Contracts::CreateService.call(
          organization: current_organization,
          params: create_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_contract(result.contract)
        else
          render_error_response(result)
        end
      end

      def index
        filters = params.permit(:plan_code, :external_customer_id, :external_id, status: [])
        filters[:status] = ["active"] if filters[:status].blank?

        result = ::ContractsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters:
        )

        if result.success?
          contracts = result.contracts.includes(:plan, :customer)

          # One grouped query instead of one COUNT per row in the serializer.
          applied_rate_cards_counts = ContractRateCard.current_and_scheduled
            .where(contract_id: contracts.map(&:id))
            .group(:contract_id)
            .count

          render(
            json: ::CollectionSerializer.new(
              contracts,
              ::V2::ContractSerializer,
              collection_name: "contracts",
              meta: pagination_metadata(contracts),
              applied_rate_cards_counts:
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        contract = current_organization.contracts
          .order(started_at: :desc)
          .find_by(external_id: params[:external_id], status: requested_status)
        return not_found_error(resource: "contract") unless contract

        render(
          json: ::V2::ContractSerializer.new(
            contract,
            root_name: "contract",
            includes: %i[applied_rate_cards]
          )
        )
      end

      private

      # The column is a PostgreSQL enum: an unknown value would be a
      # database-level cast error, so anything else falls back to active.
      def requested_status
        if Contract::STATUSES.value?(params[:status])
          params[:status]
        else
          "active"
        end
      end

      def create_params
        params.require(:contract).permit(
          :external_customer_id,
          :external_id,
          :name,
          :plan_code,
          :billing_time,
          :billing_anchor_date,
          :started_at,
          :ended_at
        )
      end

      def render_contract(contract)
        render(json: ::V2::ContractSerializer.new(contract, root_name: "contract", includes: %i[applied_rate_cards]))
      end

      def resource_name
        "contract"
      end
    end
  end
end
