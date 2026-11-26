# frozen_string_literal: true

module Api
  module V2
    class ContractsController < Api::V2::BaseController
      include Api::V2::ContractLookup

      cursor_paginated_index(Contract)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::ContractSerializer, expand_on: %i[show publish]

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
        contract = find_contract(params[:external_id])

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
        contract = find_contract(params[:external_id])

        result = ::Contracts::TerminateService.call(contract:)

        if result.success?
          render_contract(result.contract)
        else
          render_error_response(result)
        end
      end

      # Releases a draft for billing. A retry is safe: it publishes nothing again,
      # and activates a pending contract whose start has passed.
      def publish
        contract = find_contract(params[:external_id])

        result = ::Contracts::PublishService.call(contract:)

        if result.success?
          render_contract(result.contract)
        else
          render_error_response(result)
        end
      end

      def index
        filters = params.permit(:plan_code, :external_customer_id, :external_id, :has_rate_overrides, billing_entity_ids: [])
          .to_h.merge(date_range_filters)
        filters[:status] = Array.wrap(params[:status]).compact_blank.presence

        result = ::ContractsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters:,
          search_term: params[:search_term]
        )

        if result.success?
          render_contracts(result.contracts.includes(:catalog_plan, customer: :billing_entity))
        else
          render_error_response(result)
        end
      end

      def show
        contract = find_contract(params[:external_id])
        return not_found_error(resource: "contract") unless contract

        render_contract(contract)
      end

      private

      def create_params
        permitted = params.require(:contract).permit(
          :external_customer_id,
          :external_id,
          :code,
          :name,
          :plan_code,
          :status,
          :billing_anchor_date,
          :started_at,
          :ended_at,
          :consolidate_invoice,
          :purchase_order_number,
          invoice_custom_section: [:skip_invoice_custom_sections, {invoice_custom_section_codes: []}]
        )

        keep_status(permitted)
      end

      # external_customer_id and external_id are set at creation and address the
      # contract. Contracts::UpdateService decides which of the rest may change
      # for the contract's status.
      def update_params
        permitted = params.require(:contract).permit(
          :name,
          :plan_code,
          :status,
          :billing_anchor_date,
          :started_at,
          :ended_at,
          :consolidate_invoice,
          :purchase_order_number,
          invoice_custom_section: [:skip_invoice_custom_sections, {invoice_custom_section_codes: []}]
        )

        keep_status(permitted)
      end

      # permit drops a non-scalar status, which the services would then read as
      # omitted (a contract that bills instead of a draft, an ignored update):
      # keep it so they refuse it.
      def keep_status(permitted)
        if params[:contract].key?(:status) && !permitted.key?(:status)
          permitted[:status] = params[:contract][:status].to_s
        end

        permitted
      end

      def resource_name
        "contract"
      end
    end
  end
end
