# frozen_string_literal: true

module Api
  module V1
    class CreditNotesController < Api::BaseController
      def show
        credit_note = current_organization.credit_notes.find_by(id: params[:id])
        return not_found_error(resource: 'credit_note') unless credit_note

        render(
          json: ::V1::CreditNoteSerializer.new(
            credit_note,
            root_name: 'credit_note',
            includes: %i[items],
          ),
        )
      end

      def index
        credit_notes = current_organization.credit_notes

        if params[:external_customer_id]
          credit_notes = credit_notes.joins(:customer).where(customers: { external_id: params[:external_customer_id] })
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
          ),
        )
      end
    end
  end
end
