# frozen_string_literal: true

module PaymentIndex
  include Pagination
  extend ActiveSupport::Concern

  WHITELIST = [
    :page, :per_page, :invoice_id, :external_customer_id, :currency, :search_term,
    :amount_from, :amount_to, :receipt_number, :invoice_number, :created_at_from, :created_at_to,
    :payment_status, :payment_statuses, :payment_provider_type, :payment_type, :payable_type,
    {payment_status: [], payment_statuses: [], payment_provider_type: [], payment_type: [], payable_type: []}
  ].freeze

  def payment_index(customer_external_id: nil)
    result = PaymentsQuery.call(
      organization: current_organization,
      pagination: {
        page: params[:page],
        limit: params[:per_page] || PER_PAGE
      },
      search_term: params[:search_term],
      filters: {
        invoice_id: params[:invoice_id],
        external_customer_id: customer_external_id,
        currency: params[:currency],
        amount_from: params[:amount_from],
        amount_to: params[:amount_to],
        receipt_number: params[:receipt_number],
        invoice_number: params[:invoice_number],
        created_at_from: (Date.iso8601(params[:created_at_from]) if valid_date?(params[:created_at_from])),
        created_at_to: (Date.iso8601(params[:created_at_to]) if valid_date?(params[:created_at_to])),
        payment_status: params[:payment_status] || params[:payment_statuses],
        payment_provider_type: params[:payment_provider_type],
        payment_type: params[:payment_type],
        payable_type: params[:payable_type]
      }
    )

    if result.success?
      render(
        json: ::CollectionSerializer.new(
          result.payments.includes(
            :payment_provider_customer,
            :payment_provider,
            payable: :customer
          ),
          ::V1::PaymentSerializer,
          collection_name: resource_name.pluralize,
          meta: pagination_metadata(result.payments, params: params.permit(*WHITELIST))
        )
      )
    else
      render_error_response(result)
    end
  end
end
