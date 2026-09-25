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

      def update
        contract = current_organization.contracts.live_by_external_id(params[:external_id])

        result = ::Contracts::UpdateService.call(
          contract:,
          params: update_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_contract(result.contract)
        else
          render_error_response(result)
        end
      end

      # A contract is never destroyed: DELETE ends its lifecycle. An active
      # contract is terminated, a pending one canceled — the service decides.
      def terminate
        contract = current_organization.contracts.terminatable_by_external_id(params[:external_id])

        result = ::Contracts::TerminateService.call(contract:)

        if result.success?
          render_contract(result.contract)
        else
          render_error_response(result)
        end
      end

      def index
        filters = params.permit(:plan_code, :external_customer_id, :external_id, :has_rate_overrides, billing_entity_ids: [])
        # Accept both ?status=pending and ?status[]=pending — strong params
        # would silently drop the scalar form and hand back active contracts
        # to a caller who believes they filtered.
        statuses = params[:status].is_a?(Array) ? params[:status] : [params[:status]]
        filters[:status] = statuses.compact_blank.presence || ["active"]

        result = ::ContractsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters:,
          search_term: params[:search_term]
        )

        if result.success?
          contracts = result.contracts.includes(:catalog_plan, :customer)

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
        # No status filter resolves to the live contract (pending or active),
        # so a pending contract is visible on its own detail URL and matches
        # what the nested applied-rate-card endpoints operate on. An explicit
        # status reads a specific one, including terminated/canceled history.
        contract =
          if params[:status].present?
            current_organization.contracts
              .order(started_at: :desc)
              .find_by(external_id: params[:external_id], status: requested_status)
          else
            current_organization.contracts.live_by_external_id(params[:external_id])
          end
        return not_found_error(resource: "contract") unless contract

        render(
          json: ::V2::ContractSerializer.new(
            contract,
            root_name: "contract",
            includes: %i[applied_rate_cards]
          )
        )
      end

      # Testing helper
      def segments
        contracts = requested_contracts
        return not_found_error(resource: "contract") unless contracts

        errors = invalid_date_params
        return validation_errors(errors:) if errors.any?

        result = ::BillingSegments::PreviewService.call(
          contracts:,
          from: window_start(contracts),
          to: window_end
        )

        if result.success?
          payload = ::CollectionSerializer.new(
            result.previews,
            ::V2::BillableSegmentSerializer,
            collection_name: "segments"
          ).serialize
          payload[:next_billing_at] = result.next_billing_at.iso8601 if result.next_billing_at

          render json: payload
        else
          render_error_response(result)
        end
      end

      # Testing helper
      def bill
        contracts = requested_contracts
        return not_found_error(resource: "contract") unless contracts

        errors = invalid_date_params
        # Billing resumes from each card's own clock, so there is no start date to honour.
        # Refusing the parameter beats accepting it and silently ignoring it.
        errors[:start_on] = ["value_is_invalid"] if params[:start_on].present?
        return validation_errors(errors:) if errors.any?

        result = ::Contracts::BillService.call(contracts:, timestamp: window_end)

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.invoices,
              ::V1::InvoiceSerializer,
              collection_name: "invoices",
              includes: %i[customer fees]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def contract_external_ids
        @contract_external_ids ||= Array.wrap(
          params[:external_ids].presence ||
            params[:contract_external_ids].presence ||
            params[:external_id]
        ).map(&:to_s).reject(&:blank?).uniq
      end

      # One lookup per id rather than a single WHERE IN: an external id can address both a
      # pending contract and its active sibling, and live_by_external_id is what picks between
      # them everywhere else. An unknown id answers nothing at all rather than the subset —
      # a typo in a QA call should be visible, not look like "that one had nothing to bill".
      def requested_contracts
        return if contract_external_ids.empty?

        contracts = contract_external_ids.map { current_organization.contracts.live_by_external_id(it) }
        return if contracts.any?(&:nil?)

        contracts
      end

      def window_start(contracts)
        if params[:start_on].present?
          params[:start_on].to_date.beginning_of_day
        else
          contracts.filter_map(&:started_at).min || Time.current
        end
      end

      def window_end
        if params[:end_on].present?
          params[:end_on].to_date.end_of_day
        else
          Time.current
        end
      end

      # String#to_date raises Date::Error on a malformed value and nothing above this
      # rescues it, so an unparseable date would answer 500 instead of naming the param.
      def invalid_date_params
        %i[start_on end_on]
          .select { params[it].present? && !parsable_date?(it) }
          .index_with { ["invalid_date"] }
      end

      def parsable_date?(key)
        params[key].to_date
        true
      rescue Date::Error
        false
      end

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

      # external_customer_id and external_id are set at creation and address the
      # contract. Contracts::UpdateService decides which of the rest may change
      # for the contract's status.
      def update_params
        params.require(:contract).permit(
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
