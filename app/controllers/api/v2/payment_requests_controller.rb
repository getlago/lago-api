# frozen_string_literal: true

module Api
  module V2
    class PaymentRequestsController < BaseController
      cursor_paginated_index(PaymentRequest)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::PaymentRequestSerializer

      before_action :set_billing_entity_ids, only: :index

      def index
        filters = index_filters
        payment_status = filters[:payment_status]

        if payment_status.present? && !PaymentRequest.payment_statuses.key?(payment_status)
          return validation_errors(errors: {payment_status: ["value_is_invalid"]})
        end

        result = ::PaymentRequestsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters:
        )

        if result.success?
          render_payment_requests(result.payment_requests.preload(::V2::PaymentRequestSerializer::PRELOADS))
        else
          render_error_response(result)
        end
      end

      def show
        payment_request = current_organization.payment_requests
          .preload(::V2::PaymentRequestSerializer::PRELOADS)
          .find_by(id: params[:id])

        if payment_request
          render_payment_request(payment_request)
        else
          not_found_error(resource: resource_name)
        end
      end

      def create
        result = ::PaymentRequests::CreateService.call(organization: current_organization, params: create_params)

        if result.success?
          render_payment_request(result.payment_request)
        else
          render_error_response(result)
        end
      end

      private

      def index_filters
        params.permit(:external_customer_id, :payment_status, :currency)
          .to_h.symbolize_keys.merge(billing_entity_ids: @billing_entity_ids, **date_range_filters)
      end

      def set_billing_entity_ids
        permitted_params = params.permit(:billing_entity_codes, billing_entity_codes: [])
        codes = Array(permitted_params[:billing_entity_codes]).uniq
        return if codes.blank?

        @billing_entity_ids = current_organization.all_billing_entities.where(code: codes).ids

        if @billing_entity_ids.size != codes.size
          not_found_error(resource: "billing_entity")
        end
      end

      def create_params
        input = params.require(:payment_request)
        unless input.is_a?(ActionController::Parameters)
          raise ActionController::ParameterMissing, :payment_request
        end

        input.permit(
          :email,
          :external_customer_id,
          lago_invoice_ids: [],
          payment_method: %i[payment_method_type payment_method_id]
        ).to_h.deep_symbolize_keys
      end

      def resource_name
        "payment_request"
      end
    end
  end
end
