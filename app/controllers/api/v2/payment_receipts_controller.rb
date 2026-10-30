# frozen_string_literal: true

module Api
  module V2
    class PaymentReceiptsController < Api::V2::BaseController
      cursor_paginated_index(PaymentReceipt)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::PaymentReceiptSerializer

      def index
        result = ::PaymentReceiptsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: params.permit(:invoice_id).to_h.symbolize_keys.merge(date_range_filters)
        )

        if result.success?
          render_payment_receipts(result.payment_receipts.preload(::V2::PaymentReceiptSerializer::PRELOADS))
        else
          render_error_response(result)
        end
      end

      def show
        payment_receipt = find_payment_receipt

        if payment_receipt
          render_payment_receipt(payment_receipt)
        else
          not_found_error(resource: "payment_receipt")
        end
      end

      def resend_email
        payment_receipt = find_payment_receipt
        return not_found_error(resource: "payment_receipt") unless payment_receipt

        result = ::Emails::ResendService.call(
          resource: payment_receipt,
          to: resend_email_params[:to],
          cc: resend_email_params[:cc],
          bcc: resend_email_params[:bcc]
        )

        if result.success?
          head(:ok)
        else
          render_error_response(result)
        end
      end

      private

      def find_payment_receipt
        current_organization.payment_receipts.find_by(id: params[:id])
      end

      def resend_email_params
        params.permit(to: [], cc: [], bcc: [])
      end

      def resource_name
        "payment_receipt"
      end
    end
  end
end
