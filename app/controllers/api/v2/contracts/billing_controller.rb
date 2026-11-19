# frozen_string_literal: true

module Api
  module V2
    module Contracts
      class BillingController < Api::V2::BaseController
        include Api::V2::ContractLookup

        before_action :load_contracts
        before_action :read_dates

        def operations
          result = ::BillingObligations::PreviewService.call(contracts: @contracts, start_on: @start_on, end_on: @end_on)
          return render_error_response(result) unless result.success?

          payload = ::CollectionSerializer.new(result.billing_obligations, ::V2::BillingObligationSerializer,
            collection_name: :billing_obligations, includes: Api::Serializable::TIMESTAMP_INCLUDES).serialize
          payload[:next_billing_at] = result.next_billing_at.utc.iso8601(6) if result.next_billing_at
          render json: payload
        end

        def bill
          result = ::Contracts::BillService.call(contracts: @contracts, end_on: @end_on)
          return render_error_response(result) unless result.success?

          render json: ::CollectionSerializer.new(result.invoices, ::V1::InvoiceSerializer,
            collection_name: :invoices, includes: %i[customer fees])
        end

        private

        def resource_name = "contract"

        def load_contracts
          ids = Array.wrap(params[:external_ids] || params[:contract_external_ids] || params[:external_id]).uniq
          @contracts = ids.map do |id|
            find_contract(id) if id.is_a?(String) && id.present?
          end
          not_found_error(resource: "contract") if @contracts.empty? || @contracts.any?(&:nil?)
        end

        def read_dates
          @start_on = Utils::Datetime.parse_iso8601_date(params[:start_on])
          @end_on = Utils::Datetime.parse_iso8601_date(params[:end_on])
          errors = {}
          if params.key?(:start_on)
            if action_name == "bill"
              errors[:start_on] = ["value_is_invalid"]
            elsif !@start_on
              errors[:start_on] = ["invalid_date"]
            end
          end
          errors[:end_on] = ["invalid_date"] if params.key?(:end_on) && !@end_on
          errors[:end_on] = ["value_is_invalid"] if @start_on && @end_on && @end_on < @start_on
          validation_errors(errors:) if errors.any?
        end
      end
    end
  end
end
