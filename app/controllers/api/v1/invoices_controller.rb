# frozen_string_literal: true

module Api
  module V1
    class InvoicesController < Api::BaseController
      def update
        service = Invoices::UpdateService.new
        result = service.update_from_api(
          invoice_id: params[:id],
          params: update_params,
        )

        if result.success?
          render_invoice(result.invoice)
        else
          validation_errors(result)
        end
      end

      def show
        invoice = Invoice.find_by(id: params[:id])

        return not_found_error unless invoice

        render_invoice(invoice)
      end

      def index
        invoices = current_organization.invoices
                                       .where(date_from_criteria)
                                       .where(date_to_criteria)
                                       .order(created_at: :desc)
                                       .page(params[:page])
                                       .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            invoices,
            ::V1::InvoiceSerializer,
            collection_name: 'invoices',
            meta: pagination_metadata(invoices),
          ),
        )
      end

      private

      def update_params
        params.require(:invoice).permit(:status)
      end

      def render_invoice(invoice)
        render(
          json: ::V1::InvoiceSerializer.new(
            invoice,
            root_name: 'invoice',
            includes: %i[customer subscription fees],
          ),
        )
      end

      def date_from_criteria
        return {} unless params[:issuing_date_from]

        date_from = Date._strptime(params[:issuing_date_from])

        return {} unless date_from

        {issuing_date: Date.new(date_from[:year], date_from[:mon], date_from[:mday])..}
      end

      def date_to_criteria
        return {} unless params[:issuing_date_to]

        date_to = Date._strptime(params[:issuing_date_to])

        return {} unless date_to

        {issuing_date: ..Date.new(date_to[:year], date_to[:mon], date_to[:mday])}
      end
    end
  end
end
