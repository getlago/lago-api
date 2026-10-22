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
        invoice = current_organization.invoices.visible.product_catalog.find_by(id: params[:id])
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
        invoice = current_organization.invoices.visible.find_by(id: params[:id])

        result = ::Invoices::VoidService.call(invoice:, params: params.permit(:generate_credit_note, :refund_amount, :credit_amount))

        if result.success?
          render_v1_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      private

      # The v1 invoice payload until the v2 invoice serializer exists.
      def render_v1_invoice(invoice)
        render(
          json: ::V1::InvoiceSerializer.new(
            invoice,
            root_name: "invoice",
            includes: %i[customer integration_customers billing_periods subscriptions fees credits metadata applied_taxes error_details applied_invoice_custom_sections]
          )
        )
      end

      def resource_name
        "invoice"
      end
    end
  end
end
