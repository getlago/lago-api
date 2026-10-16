# frozen_string_literal: true

module Api
  module V2
    # The cursor-paginated list of catalog invoices, for the organization and per customer.
    module InvoiceIndex
      extend ActiveSupport::Concern

      # Public value => stored enum.
      INVOICE_TYPES = {"contract" => "contract", "advance_fees" => "advance_charges"}.freeze

      included do
        cursor_paginated_index(Invoice)
      end

      private

      def invoice_index(customer: nil)
        filters = index_filters

        if filters[:invoice_type].present? && !INVOICE_TYPES.key?(filters[:invoice_type])
          return validation_errors(errors: {invoice_type: ["value_is_invalid"]})
        end

        billing_entity_codes = Array(filters[:billing_entity_codes]).uniq
        if billing_entity_codes.any?
          billing_entity_ids = current_organization.all_billing_entities.where(code: billing_entity_codes).ids
          return not_found_error(resource: "billing_entity") if billing_entity_ids.size != billing_entity_codes.size
        end

        result = ::InvoicesQuery.call(
          organization: current_organization,
          pagination: cursor,
          search_term: filters[:search_term],
          filters: {
            amount_from: filters[:amount_from],
            amount_to: filters[:amount_to],
            billing_entity_ids:,
            currency: filters[:currency],
            customer_id: customer&.id,
            invoice_type: INVOICE_TYPES[filters[:invoice_type]],
            issuing_date_from: filters[:issuing_date_from],
            issuing_date_to: filters[:issuing_date_to],
            partially_paid: filters[:partially_paid],
            payment_dispute_lost: filters[:payment_dispute_lost],
            payment_overdue: filters[:payment_overdue],
            payment_status: filters[:payment_status] || filters[:payment_statuses],
            product_catalog: true,
            purchase_order_number: filters[:purchase_order_number],
            settlements: filters[:settlements],
            status: filters[:status] || filters[:statuses]
          }
        )

        if result.success?
          page = ::CursorPagination::Page.new(records: result.invoices.preload(:billing_entity), cursor:)
          Invoice.preload_aggregations(page.records, :offset_amount_cents)

          render(
            json: ::CollectionSerializer.new(
              page.records,
              ::V2::InvoiceSerializer,
              collection_name: "invoices",
              meta: page.meta
            )
          )
        else
          render_error_response(result)
        end
      end

      def index_filters
        params.permit(
          :amount_from,
          :amount_to,
          :billing_entity_codes,
          :currency,
          :invoice_type,
          :issuing_date_from,
          :issuing_date_to,
          :partially_paid,
          :payment_dispute_lost,
          :payment_overdue,
          :payment_status,
          :purchase_order_number,
          :search_term,
          :settlements,
          :status,
          billing_entity_codes: [],
          payment_status: [],
          payment_statuses: [],
          settlements: [],
          status: [],
          statuses: []
        )
      end
    end
  end
end
