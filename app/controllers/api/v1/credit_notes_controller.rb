# frozen_string_literal: true

module Api
  module V1
    class CreditNotesController < Api::BaseController
      def create
        result = CreditNotes::CreateService.call(
          invoice: current_organization.invoices.visible.find_by(id: input_params[:invoice_id]),
          **input_params
        )

        if result.success?
          render(
            json: ::V1::CreditNoteSerializer.new(
              result.credit_note,
              root_name: "credit_note",
              includes: %i[items applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        credit_note = current_organization.credit_notes.finalized.find_by(id: params[:id])
        return not_found_error(resource: "credit_note") unless credit_note

        render(
          json: ::V1::CreditNoteSerializer.new(
            credit_note,
            root_name: "credit_note",
            includes: %i[items applied_taxes error_details]
          )
        )
      end

      def update
        credit_note = current_organization.credit_notes.find_by(id: params[:id])
        return not_found_error(resource: "credit_note") unless credit_note

        result = CreditNotes::UpdateService.new(credit_note:, **update_params).call

        if result.success?
          render(
            json: ::V1::CreditNoteSerializer.new(
              credit_note,
              root_name: "credit_note",
              includes: %i[items applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def download
        credit_note = current_organization.credit_notes.finalized.find_by(id: params[:id])
        return not_found_error(resource: "credit_note") unless credit_note

        if credit_note.file.present?
          return render(
            json: ::V1::CreditNoteSerializer.new(
              credit_note,
              root_name: "credit_note"
            )
          )
        end

        CreditNotes::GeneratePdfJob.perform_later(credit_note)

        head(:ok)
      end

      def void
        credit_note = current_organization.credit_notes.find_by(id: params[:id])
        return not_found_error(resource: "credit_note") unless credit_note

        result = CreditNotes::VoidService.new(credit_note:).call

        if result.success?
          render(
            json: ::V1::CreditNoteSerializer.new(
              credit_note,
              root_name: "credit_note",
              includes: %i[items applied_taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def index
        billing_entities = current_organization.billing_entities.where(code: params[:billing_entity_codes]) if params[:billing_entity_codes].present?
        return not_found_error(resource: "billing_entity") if params[:billing_entity_codes].present? && billing_entities.count != params[:billing_entity_codes].count

        result = CreditNotesQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          search_term: params[:search_term],
          filters: {
            amount_from: params[:amount_from],
            amount_to: params[:amount_to],
            billing_entity_ids: billing_entities&.ids,
            credit_status: params[:credit_status],
            currency: params[:currency],
            customer_external_id: params[:external_customer_id],
            invoice_number: params[:invoice_number],
            issuing_date_from: (Date.strptime(params[:issuing_date_from]) if valid_date?(params[:issuing_date_from])),
            issuing_date_to: (Date.strptime(params[:issuing_date_to]) if valid_date?(params[:issuing_date_to])),
            reason: params[:reason],
            refund_status: params[:refund_status],
            self_billed: params[:self_billed]
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.credit_notes.includes(:items, :applied_taxes, :invoice),
              ::V1::CreditNoteSerializer,
              collection_name: "credit_notes",
              meta: pagination_metadata(result.credit_notes),
              includes: %i[items applied_taxes error_details]
            )
          )
        else
          render_error_response(result)
        end
      end

      def estimate
        result = CreditNotes::EstimateService.call(
          invoice: current_organization.invoices.visible.find_by(id: estimate_params[:invoice_id]),
          items: estimate_params[:items]
        )

        if result.success?
          render(
            json: ::V1::CreditNotes::EstimateSerializer.new(
              result.credit_note,
              root_name: "estimated_credit_note"
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        @input_params ||= params.expect(
          credit_note: [
            :invoice_id,
            :reason,
            :description,
            :credit_amount_cents,
            :refund_amount_cents,
            items: [
              :fee_id,
              :amount_cents
            ]
          ]
        )
      end

      def update_params
        params.expect(credit_note: [:refund_status])
      end

      def estimate_params
        @estimate_params ||= params.expect(
          credit_note: [
            :invoice_id,
            items: [
              :fee_id,
              :amount_cents
            ]
          ]
        )
      end

      def resource_name
        "credit_note"
      end
    end
  end
end
