# frozen_string_literal: true

module Api
  module V2
    class FeesController < Api::V2::BaseController
      cursor_paginated_index(Fee)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::FeeSerializer

      def index
        result = ::ProductFeesQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: index_filters
        )

        if result.success?
          render_fees(result.fees.preload(::V2::FeeSerializer::PRELOADS))
        else
          render_error_response(result)
        end
      end

      def show
        return not_found_error(resource: "fee") unless fee

        render_fee(fee)
      end

      def update
        return not_found_error(resource: "fee") unless fee

        result = ::Fees::UpdateService.call(fee:, params: params.require(:fee).permit(:payment_status))

        if result.success?
          render_fee(result.fee)
        else
          render_error_response(result)
        end
      end

      def destroy
        return not_found_error(resource: "fee") unless fee

        result = ::Fees::DestroyService.call(fee:)

        if result.success?
          render_fee(result.fee)
        else
          render_error_response(result)
        end
      end

      private

      # Legacy fees are served by v1: on v2 they do not exist.
      def fee
        @fee ||= Fee.where(organization: current_organization).product.find_by(id: params[:id])
      end

      def index_filters
        params.permit(
          :lago_invoice_id,
          :payment_status,
          :external_customer_id,
          :external_contract_id,
          :product_code,
          :rate_card_code,
          :currency,
          :event_transaction_id,
          :succeeded_at_from,
          :succeeded_at_to,
          :failed_at_from,
          :failed_at_to,
          :refunded_at_from,
          :refunded_at_to
        ).to_h.merge(date_range_filters)
      end

      def resource_name
        "fee"
      end
    end
  end
end
