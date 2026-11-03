# frozen_string_literal: true

module Api
  module V2
    # The cursor-paginated credit-note list for organizations and their customers.
    module CreditNoteIndex
      extend ActiveSupport::Concern

      PRELOADS = [
        :items,
        invoice: :billing_entity,
        file_attachment: :blob,
        xml_file_attachment: :blob
      ].freeze

      included do
        cursor_paginated_index(CreditNote)
      end

      private

      def credit_note_index(customer: nil)
        billing_entity_codes = index_filters[:billing_entity_codes]
        billing_entities = current_organization.billing_entities.where(code: billing_entity_codes) if billing_entity_codes.present?
        return not_found_error(resource: "billing_entity") if billing_entity_codes.present? && billing_entities.count != billing_entity_codes.uniq.count

        result = ::CreditNotesQuery.call(
          organization: current_organization,
          includes: PRELOADS,
          pagination: cursor,
          search_term: index_filters[:search_term],
          filters: credit_note_filters(billing_entities&.ids, customer:)
        )

        if result.success?
          render_credit_notes(result.credit_notes)
        else
          render_error_response(result)
        end
      end

      def index_filters
        params.permit(
          :search_term, :external_customer_id, :amount_from, :amount_to, :credit_status, :currency,
          :invoice_number, :purchase_order_number, :issuing_date_from, :issuing_date_to, :reason,
          :refund_status, :self_billed, billing_entity_codes: [], types: []
        )
      end

      def credit_note_filters(billing_entity_ids, customer: nil)
        filters = index_filters.to_h.symbolize_keys
        filters.delete(:search_term)
        filters.delete(:billing_entity_codes)
        filters[:customer_external_id] = filters.delete(:external_customer_id)
        filters[:billing_entity_ids] = billing_entity_ids
        filters[:customer_id] = customer.id if customer
        %i[issuing_date_from issuing_date_to].each do |key|
          filters[key] = Date.iso8601(filters[key]) if valid_date?(filters[key])
        end
        filters
      end
    end
  end
end
