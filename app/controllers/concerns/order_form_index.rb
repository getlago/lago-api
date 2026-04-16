# frozen_string_literal: true

module OrderFormIndex
  include Pagination
  extend ActiveSupport::Concern

  def order_form_index(customer_external_id: nil)
    filters = params.permit(:status)
    filters[:external_customer_id] = customer_external_id

    result = OrderFormsQuery.call(
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
          result.order_forms,
          ::V1::OrderFormSerializer,
          collection_name: "order_forms",
          meta: pagination_metadata(result.order_forms)
        )
      )
    else
      render_error_response(result)
    end
  end
end
