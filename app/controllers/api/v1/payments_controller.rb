# frozen_string_literal: true

module Api
  module V1
    class PaymentsController < Api::BaseController
      def create
        result = Payments::ManualCreateService.call(
          organization: current_organization,
          params: create_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render(
            json: ::V1::PaymentSerializer.new(result.payment, root_name: resource_name)
          )
        else
          render_error_response(result)
        end
      end

      def index
        result = PaymentsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: index_filters
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.payments,
              ::V1::PaymentSerializer,
              collection_name: resource_name.pluralize,
              meta: pagination_metadata(result.payments)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        payment = Payment.for_organization(current_organization).find_by(id: params[:id])
        return not_found_error(resource: resource_name) unless payment

        render_payment(payment)
      end

      private

      def create_params
        params.require(:payment).permit(
          :invoice_id,
          :amount_cents,
          :reference,
          :paid_at
        )
      end

      def index_filters
        params.permit(:invoice_id, :external_customer_id)
      end

      def render_payment(payment)
        render(
          json: ::V1::PaymentSerializer.new(
            payment,
            root_name: resource_name
          )
        )
      end

      def resource_name
        'payment'
      end
    end
  end
end
