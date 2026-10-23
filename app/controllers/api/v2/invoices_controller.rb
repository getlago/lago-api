# frozen_string_literal: true

module Api
  module V2
    class InvoicesController < BaseController
      include Api::V2::InvoiceIndex

      serializable_with ::V2::InvoiceSerializer

      # Beyond this, the fees of an invoice are paged through GET /api/v2/fees?lago_invoice_id=.
      MAX_EXPANDED_FEES = 1_000

      def index
        invoice_index
      end

      def show
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        fees_count = invoice.fees.product.count if requested_expansions.include?(:fees)
        if fees_count.to_i > MAX_EXPANDED_FEES
          return invalid_request_error(
            code: "expansion_too_large",
            error_details: {expands: {fees: {count: fees_count, max: MAX_EXPANDED_FEES}}}
          )
        end

        render_invoice(invoice)
      end

      def void
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::VoidService.call(invoice:, params: params.permit(:generate_credit_note, :refund_amount, :credit_amount))

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def download_pdf
        invoice = find_invoice(:finalized)
        return not_found_error(resource: "invoice") unless invoice

        if invoice.file.present?
          return render_invoice(invoice)
        end

        ::Invoices::GeneratePdfJob.perform_later(invoice)

        head(:ok)
      end

      def resend_email
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Emails::ResendService.call(
          resource: invoice,
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

      def retry
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::RetryService.call(invoice:)

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def retry_payment
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::Payments::RetryService.call(
          invoice:,
          payment_method_params: retry_payment_params[:payment_method]
        )

        if result.success?
          head(:ok)
        else
          render_error_response(result)
        end
      end

      def payment_url
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::Payments::GeneratePaymentUrlService.call(invoice:)

        if result.success?
          render(
            json: ::V2::Invoices::PaymentUrlSerializer.new(
              invoice,
              root_name: "invoice_payment_details",
              payment_url: result.payment_url
            )
          )
        else
          render_error_response(result)
        end
      end

      def finalize
        invoice = find_invoice(:draft)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::RefreshDraftAndFinalizeService.call(invoice:)

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def refresh
        invoice = find_invoice(:visible)
        return not_found_error(resource: "invoice") unless invoice

        result = ::Invoices::RefreshDraftService.call(invoice:)

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      private

      def find_invoice(status_scope)
        current_organization.invoices.public_send(status_scope).product_catalog.find_by(id: params[:id])
      end

      def resend_email_params
        params.permit(to: [], cc: [], bcc: [])
      end

      def retry_payment_params
        params.permit(payment_method: [:payment_method_type, :payment_method_id]).to_h.deep_symbolize_keys
      end

      def resource_name
        "invoice"
      end
    end
  end
end
