# frozen_string_literal: true

module Api
  module V1
    class CreditNotesController < Api::BaseController
      def create
        service = CreditNotes::CreateService.new(
          invoice: current_organization.invoices.not_generating.find_by(id: input_params[:invoice_id]),
          **input_params
        )
        result = service.call

        if result.success?
          render(
            json: ::V1::CreditNoteSerializer.new(
              result.credit_note,
              root_name: 'credit_note',
              includes: %i[items applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        credit_note = current_organization.credit_notes.finalized.find_by(id: params[:id])
        return not_found_error(resource: 'credit_note') unless credit_note

        render(
          json: ::V1::CreditNoteSerializer.new(
            credit_note,
            root_name: 'credit_note',
            includes: %i[items applied_taxes]
          )
        )
      end

      def update
        credit_note = current_organization.credit_notes.find_by(id: params[:id])
        return not_found_error(resource: 'credit_note') unless credit_note

        result = CreditNotes::UpdateService.new(credit_note:, **update_params).call

        if result.success?
          render(
            json: ::V1::CreditNoteSerializer.new(
              credit_note,
              root_name: 'credit_note',
              includes: %i[items applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def download
        credit_note = current_organization.credit_notes.finalized.find_by(id: params[:id])
        return not_found_error(resource: 'credit_note') unless credit_note

        if credit_note.file.present?
          return render(
            json: ::V1::CreditNoteSerializer.new(
              credit_note,
              root_name: 'credit_note'
            )
          )
        end

        CreditNotes::GeneratePdfJob.perform_later(credit_note)

        head(:ok)
      end

      def void
        credit_note = current_organization.credit_notes.find_by(id: params[:id])
        return not_found_error(resource: 'credit_note') unless credit_note

        result = CreditNotes::VoidService.new(credit_note:).call

        if result.success?
          render(
            json: ::V1::CreditNoteSerializer.new(
              credit_note,
              root_name: 'credit_note',
              includes: %i[items applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def index
        credit_notes = current_organization.credit_notes.finalized

        if params[:external_customer_id]
          credit_notes = credit_notes.joins(:customer).where(customers: {external_id: params[:external_customer_id]})
        end

        credit_notes = credit_notes.order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            credit_notes,
            ::V1::CreditNoteSerializer,
            collection_name: 'credit_notes',
            meta: pagination_metadata(credit_notes),
            includes: %i[items applied_taxes]
          )
        )
      end

      def estimate
        result = CreditNotes::EstimateService.call(
          invoice: current_organization.invoices.not_generating.find_by(id: estimate_params[:invoice_id]),
          items: estimate_params[:items]
        )

        if result.success?
          render(
            json: ::V1::CreditNotes::EstimateSerializer.new(
              result.credit_note,
              root_name: 'estimated_credit_note'
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        @input_params ||= params.require(:credit_note)
          .permit(
            :invoice_id,
            :reason,
            :description,
            :credit_amount_cents,
            :refund_amount_cents,
            items: [
              :fee_id,
              :amount_cents
            ]
          )
      end

      def update_params
        params.require(:credit_note).permit(:refund_status)
      end

      def estimate_params
        @estimate_params ||= params.require(:credit_note)
          .permit(
            :invoice_id,
            items: [
              :fee_id,
              :amount_cents
            ]
          )
      end
    end
  end
end
