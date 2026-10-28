# frozen_string_literal: true

module Api
  module V2
    class CreditNotesController < Api::V2::BaseController
      PRELOADS = [
        :items,
        invoice: :billing_entity,
        file_attachment: :blob,
        xml_file_attachment: :blob
      ].freeze

      cursor_paginated_index(CreditNote)
      serializable_with ::V2::CreditNoteSerializer

      def index
        billing_entity_codes = index_filters[:billing_entity_codes]
        billing_entities = current_organization.billing_entities.where(code: billing_entity_codes) if billing_entity_codes.present?
        return not_found_error(resource: "billing_entity") if billing_entity_codes.present? && billing_entities.count != billing_entity_codes.uniq.count

        result = ::CreditNotesQuery.call(
          organization: current_organization,
          includes: PRELOADS,
          pagination: cursor,
          search_term: index_filters[:search_term],
          filters: credit_note_filters(billing_entities&.ids)
        )

        if result.success?
          render_credit_notes(result.credit_notes)
        else
          render_error_response(result)
        end
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

      def index_filters
        params.permit(
          :search_term, :external_customer_id, :amount_from, :amount_to, :credit_status, :currency,
          :invoice_number, :purchase_order_number, :issuing_date_from, :issuing_date_to, :reason,
          :refund_status, :self_billed, billing_entity_codes: [], types: []
        )
      end

      def credit_note_filters(billing_entity_ids)
        filters = index_filters.to_h.symbolize_keys
        filters.delete(:search_term)
        filters.delete(:billing_entity_codes)
        filters[:customer_external_id] = filters.delete(:external_customer_id)
        filters[:billing_entity_ids] = billing_entity_ids
        %i[issuing_date_from issuing_date_to].each do |key|
          filters[key] = Date.iso8601(filters[key]) if valid_date?(filters[key])
        end
        filters
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
