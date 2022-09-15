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
          render_error_response(result)
        end
      end

      def show
        invoice = current_organization.invoices.find_by(id: params[:id])

        return not_found_error(resource: 'invoice') unless invoice

        render_invoice(invoice)
      end

      def index
        invoices = current_organization.invoices
        if params[:external_customer_id]
          invoices = invoices.joins(:customer).where(customers: { external_id: params[:external_customer_id] })
        end
        invoices = invoices.where(date_from_criteria) if valid_date?(params[:issuing_date_from])
        invoices = invoices.where(date_to_criteria) if valid_date?(params[:issuing_date_to])
        invoices = invoices.order(created_at: :desc)
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

      def download
        invoice = current_organization.invoices.find_by(id: params[:id])

        return not_found_error(resource: 'invoice') unless invoice

        if invoice.file.present?
          return render(
            json: ::V1::InvoiceSerializer.new(
              invoice,
              root_name: 'invoice',
            ),
          )
        end

        Invoices::GenerateJob.perform_later(invoice)

        head(:ok)
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
            includes: %i[customer subscriptions fees],
          ),
        )
      end

      def date_from_criteria
        { issuing_date: Date.strptime(params[:issuing_date_from]).. }
      end

      def date_to_criteria
        { issuing_date: ..Date.strptime(params[:issuing_date_to]) }
      end
    end
  end
end
