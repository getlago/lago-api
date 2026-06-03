# frozen_string_literal: true

module SubscriptionIndex
  include Pagination
  extend ActiveSupport::Concern

  def subscription_index(external_customer_id: nil)
    billing_entity_codes = (
      Array.wrap(params[:billing_entity_codes]) +
      Array.wrap(params[:billing_entity_code])
    ).compact_blank.uniq

    if billing_entity_codes.present?
      billing_entities = current_organization.all_billing_entities.where(code: billing_entity_codes)
      return not_found_error(resource: "billing_entity") if billing_entities.count != billing_entity_codes.count
    end

    filters = params.permit(:plan_code, :overriden, :overridden, :currency, status: [])
    filters[:status] = ["active"] if filters[:status].blank?
    filters[:external_customer_id] = external_customer_id
    filters[:billing_entity_ids] = billing_entities&.ids
    result = SubscriptionsQuery.call(
      organization: current_organization,
      pagination: {
        page: params[:page],
        limit: params[:per_page] || PER_PAGE
      },
      filters: filters
    )

    if result.success?
      subscriptions = result.subscriptions
        .includes(:plan, previous_subscription: :plan, next_subscriptions: :plan, customer: :billing_entity)

      render(
        json: ::CollectionSerializer.new(
          subscriptions,
          ::V1::SubscriptionSerializer,
          collection_name: "subscriptions",
          meta: pagination_metadata(subscriptions),
          organization: current_organization
        )
      )
    else
      render_error_response(result)
    end
  end
end
