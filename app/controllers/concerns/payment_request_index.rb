# frozen_string_literal: true

module PaymentRequestIndex
  include Pagination
  extend ActiveSupport::Concern

  def payment_request_index(external_customer_id:)
    filters = params.permit(:payment_status)
    filters[:external_customer_id] = external_customer_id
    result = PaymentRequestsQuery.call(
      organization: current_organization,
      pagination: {
        page: params[:page],
        limit: params[:per_page] || PER_PAGE
      },
      filters: filters
    )

    if result.success?
      render(
        json: ::CollectionSerializer.new(
          result.payment_requests.preload(:customer, :invoices),
          ::V1::PaymentRequestSerializer,
          collection_name: "payment_requests",
          meta: pagination_metadata(result.payment_requests),
          includes: %i[customer invoices]
        )
      )
    else
      render_error_response(result)
    end
  end
end
