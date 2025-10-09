# frozen_string_literal: true

module InvoiceIndex
  include Pagination
  extend ActiveSupport::Concern

  def invoice_index(customer_external_id: nil)
    billing_entities = current_organization.all_billing_entities.where(code: params[:billing_entity_codes]) if params[:billing_entity_codes].present?
    return not_found_error(resource: "billing_entity") if params[:billing_entity_codes].present? && billing_entities.count != params[:billing_entity_codes].count

    result = InvoicesQuery.call(
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
        currency: params[:currency],
        customer_external_id: customer_external_id,
        invoice_type: params[:invoice_type],
        issuing_date_from: (Date.iso8601(params[:issuing_date_from]) if valid_date?(params[:issuing_date_from])),
        issuing_date_to: (Date.iso8601(params[:issuing_date_to]) if valid_date?(params[:issuing_date_to])),
        metadata: params[:metadata]&.permit!.to_h,
        partially_paid: params[:partially_paid],
        payment_dispute_lost: params[:payment_dispute_lost],
        payment_overdue: params[:payment_overdue],
        payment_status: params[:payment_status] || params[:payment_statuses],
        self_billed: params[:self_billed],
        status: params[:status] || params[:statuses]
      }
    )

    if result.success?
      render(
        json: ::CollectionSerializer.new(
          result.invoices.includes(:metadata, :applied_taxes, :billing_entity, :applied_usage_thresholds),
          ::V1::InvoiceSerializer,
          collection_name: "invoices",
          meta: pagination_metadata(result.invoices),
          includes: %i[customer integration_customers metadata applied_taxes]
        )
      )
    else
      render_error_response(result)
    end
  end
end
