# frozen_string_literal: true

module Api
  module V1
    class FeesController < Api::BaseController
      def show
        fee = Fee.from_organization(current_organization)
          .find_by(id: params[:id])

        return not_found_error(resource: 'fee') unless fee

        render(json: ::V1::FeeSerializer.new(fee, root_name: 'fee', includes: %i[applied_taxes]))
      end

      def update
        fee = Fee.from_organization(current_organization)
          .find_by(id: params[:id])
        result = Fees::UpdateService.call(fee:, params: update_params)

        if result.success?
          render(json: ::V1::FeeSerializer.new(fee, root_name: 'fee', includes: %i[applied_taxes]))
        else
          render_error_response(result)
        end
      end

      def index
        result = FeesQuery.call(
          organization: current_organization,
          pagination: BaseQuery::Pagination.new(
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          ),
          filters: BaseQuery::Filters.new(index_filters)
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.fees,
              ::V1::FeeSerializer,
              collection_name: 'fees',
              meta: pagination_metadata(result.fees),
              includes: %i[applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def update_params
        params.require(:fee).permit(:payment_status)
      end

      def index_filters
        params.permit(
          :fee_type,
          :payment_status,
          :external_subscription_id,
          :external_customer_id,
          :billable_metric_code,
          :currency,
          :created_at_from,
          :created_at_to,
          :failed_at_from,
          :failed_at_to,
          :succeeded_at_from,
          :succeeded_at_to,
          :refunded_at_from,
          :refunded_at_to
        )
      end
    end
  end
end
