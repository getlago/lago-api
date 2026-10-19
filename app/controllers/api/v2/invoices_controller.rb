# frozen_string_literal: true

module Api
  module V2
    class InvoicesController < BaseController
      def void
        invoice = current_organization.invoices.visible.find_by(id: params[:id])

        result = ::Invoices::VoidService.call(invoice:, params: params.permit(:generate_credit_note, :refund_amount, :credit_amount))

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      private

      # The v1 invoice payload until the v2 invoice serializer exists.
      def render_invoice(invoice)
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
