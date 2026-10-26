# frozen_string_literal: true

module Api
  module V2
    # The cursor-paginated list of catalog invoices, for the organization and per customer.
    module InvoiceIndex
      extend ActiveSupport::Concern

      # Public value => stored enum.
      INVOICE_TYPES = {"contract" => "contract", "advance_fees" => "advance_charges"}.freeze

      # The order of the v1 lists, which `index_invoices_by_cursor` was built for.
      SORT = {issuing_date: :desc, created_at: :desc, id: :asc}.freeze

      included do
        cursor_paginated_index(Invoice, sort: SORT)
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
            customer_external_id: (filters[:external_customer_id] || filters[:customer_external_id] unless customer),
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
          invoices = result.invoices.preload(:billing_entity)
          # Loads the page with the credit note offsets of all its invoices; the render reads the
          # rows the relation already holds.
          Invoice.preload_aggregations(invoices, :offset_amount_cents)

          render_invoices(invoices)
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
          :customer_external_id,
          :external_customer_id,
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
