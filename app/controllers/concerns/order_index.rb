# frozen_string_literal: true

module OrderIndex
  include Pagination
  extend ActiveSupport::Concern

  def order_index(customer_external_id: nil)
    filters = params.permit(:status, :order_type)
    filters[:external_customer_id] = customer_external_id

    result = OrdersQuery.call(
      organization: current_organization,
      pagination: {
        page: params[:page],
        limit: params[:per_page] || PER_PAGE
      },
      filters:,
      search_term: params[:search_term]
    )

    if result.success?
      render(
        json: ::CollectionSerializer.new(
          result.orders,
          ::V1::OrderSerializer,
          collection_name: "orders",
          meta: pagination_metadata(result.orders)
        )
      )
    else
      render_error_response(result)
    end
  end
end
