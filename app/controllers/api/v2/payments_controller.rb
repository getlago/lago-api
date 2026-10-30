# frozen_string_literal: true

module Api
  module V2
    class PaymentsController < Api::V2::BaseController
      cursor_paginated_index(Payment)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::PaymentSerializer

      def index
        result = ::PaymentsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: params.permit(:invoice_id, :external_customer_id).to_h.symbolize_keys.merge(date_range_filters)
        )

        if result.success?
          render_payments(result.payments.preload(::V2::PaymentSerializer::PRELOADS))
        else
          render_error_response(result)
        end
      end

      def show
        payment = Payment.for_organization(current_organization)
          .where(organization: current_organization)
          .preload(::V2::PaymentSerializer::PRELOADS)
          .find_by(id: params[:id])

        if payment
          render_payment(payment)
        else
          not_found_error(resource: resource_name)
        end
      end

      def create
        input = create_params

        # Advance-charge payments skip date validation in the shared service.
        if input[:paid_at].present? && !Utils::Datetime.valid_format?(input[:paid_at], format: :any)
          return validation_errors(errors: {paid_at: ["invalid_date"]})
        end

        result = ::Payments::ManualCreateService.call(organization: current_organization, params: input)

        if result.success?
          render_payment(result.payment)
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        input = params.require(:payment)
        unless input.is_a?(ActionController::Parameters)
          raise ActionController::ParameterMissing, :payment
        end

        input.permit(:invoice_id, :amount_cents, :reference, :paid_at).to_h.deep_symbolize_keys
      end

      def resource_name
        "payment"
      end
    end
  end
end
