# frozen_string_literal: true

module OrderFormIndex
  include Pagination
  extend ActiveSupport::Concern

  def order_form_index(customer_external_id: nil)
    filters = params.permit(
      :order_form_date_from,
      :order_form_date_to,
      :expiry_date_from,
      :expiry_date_to,
      status: [],
      external_customer_id: [],
      number: [],
      customer_id: [],
      owner_id: [],
      quote_number: []
    )
    filters[:external_customer_id] = customer_external_id if customer_external_id.present?

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
