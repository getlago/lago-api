# frozen_string_literal: true

module Api
  module V1
    class InvoicesController < Api::BaseController
      def update
        invoice = current_organization.invoices.find_by(id: params[:id])

        result = Invoices::UpdateService.new(
          invoice: invoice,
          params: update_params,
        ).call

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

        if valid_payment_status?(params[:payment_status])
          invoices = invoices.where(payment_status: params[:payment_status])
        end

        invoices = invoices.where(status: params[:status]) if valid_status?(params[:status])
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
        invoice = current_organization.invoices.finalized.find_by(id: params[:id])

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

      def refresh
        invoice = current_organization.invoices.find_by(id: params[:id])
        return not_found_error(resource: 'invoice') unless invoice

        result = Invoices::RefreshDraftService.call(invoice:)
        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def finalize
        invoice = current_organization.invoices.draft.find_by(id: params[:id])
        return not_found_error(resource: 'invoice') unless invoice

        result = Invoices::FinalizeService.call(invoice:)
        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def retry_payment
        invoice = current_organization.invoices.find_by(id: params[:id])
        return not_found_error(resource:) unless invoice

        result = Invoices::Payments::RetryService.new(invoice:).call
        return render_error_response(result) unless result.success?

        head(:ok)
      end

      private

      def update_params
        params.require(:invoice).permit(:payment_status)
      end

      def render_invoice(invoice)
        render(
          json: ::V1::InvoiceSerializer.new(
            invoice,
            root_name: 'invoice',
            includes: %i[customer subscriptions fees credits],
          ),
        )
      end

      def date_from_criteria
        { issuing_date: Date.strptime(params[:issuing_date_from]).. }
      end

      def date_to_criteria
        { issuing_date: ..Date.strptime(params[:issuing_date_to]) }
      end

      def valid_payment_status?(status)
        Invoice.payment_statuses.key?(status)
      end

      def valid_status?(status)
        Invoice.statuses.key?(status)
      end
    end
  end
end
