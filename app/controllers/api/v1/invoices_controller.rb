# frozen_string_literal: true

module Api
  module V1
    class InvoicesController < Api::BaseController
      def create
        result = Invoices::CreateOneOffService.new(
          customer:,
          currency: create_params[:currency],
          fees: create_params[:fees],
          timestamp: Time.current.to_i
        ).call

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def update
        invoice = current_organization.invoices.not_generating.find_by(id: params[:id])

        result = Invoices::UpdateService.new(
          invoice:,
          params: update_params.to_h.deep_symbolize_keys,
          webhook_notification: true
        ).call

        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def show
        invoice = current_organization.invoices.not_generating.find_by(id: params[:id])

        return not_found_error(resource: 'invoice') unless invoice

        render_invoice(invoice)
      end

      def index
        result = InvoicesQuery.new(organization: current_organization).call(
          page: params[:page],
          limit: params[:per_page] || PER_PAGE,
          search_term: params[:search_term],
          payment_status: (params[:payment_status] if valid_payment_status?(params[:payment_status])),
          payment_dispute_lost: params[:payment_dispute_lost],
          payment_overdue: (params[:payment_overdue] if %w[true false].include?(params[:payment_overdue])),
          status: (params[:status] if valid_status?(params[:status])),
          filters: {
            currency: params[:currency],
            customer_external_id: params[:external_customer_id],
            invoice_type: params[:invoice_type],
            issuing_date_from: (Date.strptime(params[:issuing_date_from]) if valid_date?(params[:issuing_date_from])),
            issuing_date_to: (Date.strptime(params[:issuing_date_to]) if valid_date?(params[:issuing_date_to]))
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.invoices,
              ::V1::InvoiceSerializer,
              collection_name: 'invoices',
              meta: pagination_metadata(result.invoices),
              includes: %i[customer metadata applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def download
        invoice = current_organization.invoices.finalized.find_by(id: params[:id])

        return not_found_error(resource: 'invoice') unless invoice

        if invoice.file.present?
          return render(
            json: ::V1::InvoiceSerializer.new(
              invoice,
              root_name: 'invoice'
            )
          )
        end

        Invoices::GeneratePdfJob.perform_later(invoice)

        head(:ok)
      end

      def refresh
        invoice = current_organization.invoices.not_generating.find_by(id: params[:id])
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

      def void
        invoice = current_organization.invoices.not_generating.find_by(id: params[:id])

        result = Invoices::VoidService.call(invoice:)
        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def lose_dispute
        invoice = current_organization.invoices.not_generating.find_by(id: params[:id])

        result = Invoices::LoseDisputeService.call(invoice:, payment_dispute_lost_at: DateTime.current)
        if result.success?
          render_invoice(result.invoice)
        else
          render_error_response(result)
        end
      end

      def retry_payment
        invoice = current_organization.invoices.not_generating.find_by(id: params[:id])
        return not_found_error(resource: 'invoice') unless invoice

        result = Invoices::Payments::RetryService.new(invoice:).call
        return render_error_response(result) unless result.success?

        head(:ok)
      end

      def payment_url
        invoice = current_organization.invoices.not_generating.includes(:customer).find_by(id: params[:id])
        return not_found_error(resource: 'invoice') unless invoice

        result = ::Invoices::Payments::GeneratePaymentUrlService.call(invoice:)

        if result.success?
          render(
            json: ::V1::PaymentProviders::InvoicePaymentSerializer.new(
              invoice,
              root_name: 'invoice_payment_details',
              payment_url: result.payment_url
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        @create_params if defined? @create_params

        @create_params =
          params.require(:invoice)
            .permit(
              :external_customer_id,
              :currency,
              fees: [
                :add_on_code,
                :invoice_display_name,
                :unit_amount_cents,
                :units,
                :description,
                {tax_codes: []}
              ]
            ).to_h.deep_symbolize_keys
      end

      def update_params
        params.require(:invoice).permit(
          :payment_status,
          metadata: [
            :id,
            :key,
            :value
          ]
        )
      end

      def render_invoice(invoice)
        render(
          json: ::V1::InvoiceSerializer.new(
            invoice,
            root_name: 'invoice',
            includes: %i[customer subscriptions fees credits metadata applied_taxes]
          )
        )
      end

      def valid_payment_status?(status)
        Invoice.payment_statuses.key?(status)
      end

      def valid_status?(status)
        Invoice.statuses.key?(status)
      end

      def customer
        Customer.find_by(
          external_id: create_params[:external_customer_id],
          organization_id: current_organization.id
        )
      end
    end
  end
end
