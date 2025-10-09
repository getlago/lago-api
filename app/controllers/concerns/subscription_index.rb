# frozen_string_literal: true

module SubscriptionIndex
  include Pagination
  extend ActiveSupport::Concern

  def subscription_index(external_customer_id: nil)
    filters = params.permit(:plan_code, status: [])
    filters[:status] = ["active"] if filters[:status].blank?
    filters[:external_customer_id] = external_customer_id
    result = SubscriptionsQuery.call(
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
          result.subscriptions,
          ::V1::SubscriptionSerializer,
          collection_name: "subscriptions",
          meta: pagination_metadata(result.subscriptions)
        )
      )
    else
      render_error_response(result)
    end
  end
end
