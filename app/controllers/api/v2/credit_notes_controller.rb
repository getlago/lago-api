# frozen_string_literal: true

module Api
  module V2
    class CreditNotesController < Api::V2::BaseController
      include Api::V2::CreditNoteIndex

      serializable_with ::V2::CreditNoteSerializer

      def index
        credit_note_index
      end

      def show
        return not_found_error(resource: "credit_note") unless finalized_credit_note

        render_credit_note(finalized_credit_note)
      end

      def create
        input = input_params
        result = ::CreditNotes::CreateService.call(
          invoice: current_organization.invoices.visible.find_by(id: input[:invoice_id]),
          **input
        )

        result.success? ? render_credit_note(result.credit_note) : render_error_response(result)
      end

      def update
        return not_found_error(resource: "credit_note") unless credit_note

        result = ::CreditNotes::UpdateService.call(credit_note:, partial_metadata: true, **update_params)
        result.success? ? render_credit_note(result.credit_note) : render_error_response(result)
      end

      def download_pdf
        download_credit_note_file(:file, ::CreditNotes::GeneratePdfJob)
      end

      def download_xml
        download_credit_note_file(:xml_file, ::CreditNotes::GenerateXmlJob)
      end

      def resend_email
        return not_found_error(resource: "credit_note") unless finalized_credit_note

        result = Emails::ResendService.call(
          resource: finalized_credit_note,
          to: resend_email_params[:to],
          cc: resend_email_params[:cc],
          bcc: resend_email_params[:bcc]
        )
        result.success? ? head(:ok) : render_error_response(result)
      end

      def void
        return not_found_error(resource: "credit_note") unless credit_note

        result = ::CreditNotes::VoidService.call(credit_note:)
        result.success? ? render_credit_note(credit_note) : render_error_response(result)
      end

      def estimate
        result = ::CreditNotes::EstimateService.call(
          invoice: current_organization.invoices.visible.find_by(id: estimate_params[:invoice_id]),
          items: estimate_params[:items]
        )

        if result.success?
          render(json: ::V2::CreditNotes::EstimateSerializer.new(
            result.credit_note,
            root_name: "estimated_credit_note",
            includes: %i[items applied_taxes usec_timestamps]
          ))
        else
          render_error_response(result)
        end
      end

      private

      def credit_note
        @credit_note ||= current_organization.credit_notes.not_deleted.find_by(id: params[:id])
      end

      def finalized_credit_note
        @finalized_credit_note ||= current_organization.credit_notes.finalized.find_by(id: params[:id])
      end

      def download_credit_note_file(file, job)
        record = finalized_credit_note
        return not_found_error(resource: "credit_note") unless record

        return render_credit_note(record) if record.public_send(file).present?

        job.perform_later(record)
        head(:ok)
      end

      def input_params
        params.require(:credit_note).permit(
          :invoice_id, :reason, :description, :credit_amount_cents, :refund_amount_cents, :offset_amount_cents,
          metadata: {}, items: %i[fee_id amount_cents]
        )
      end

      def update_params
        params.require(:credit_note).permit(:refund_status, metadata: {})
      end

      def estimate_params
        params.require(:credit_note).permit(:invoice_id, items: %i[fee_id amount_cents])
      end

      def resend_email_params
        params.permit(to: [], cc: [], bcc: [])
      end

      def resource_name
        "credit_note"
      end
    end
  end
end
