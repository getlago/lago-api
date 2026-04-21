# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    Result = BaseResult[:quote]

    def initialize(organization:, params: {})
      @organization = organization
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization
      return result.forbidden_failure! unless License.premium?
      return result.forbidden_failure! unless organization.feature_flag_enabled?(:quote)

      customer = organization.customers.find_by(id: params[:customer_id])
      return result.not_found_failure!(resource: "customer") unless customer

      subscription = nil
      if params[:subscription_id].present?
        subscription = customer.subscriptions.find_by(id: params[:subscription_id])
        return result.not_found_failure!(resource: "subscription") unless subscription
      end

      if params[:owners].present?
        invalid_ids = invalid_owner_ids(params[:owners])
        if invalid_ids.any?
          return result.single_validation_failure!(error_code: "not_found", field: :owners)
        end
      end

      # TODO: when the approve / update slice lands, enforce that `order_type: subscription_amendment`
      # requires a subscription, and that `order_type: one_off` forbids one.

      quote = Quote.transaction do
        q = organization.quotes.create!(
          customer:,
          subscription:,
          order_type: params[:order_type]
        )
        add_owners!(quote: q, owners: params[:owners]) if params[:owners].present?
        q
      end

      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params

    def invalid_owner_ids(owners)
      org_user_ids = organization.memberships.active.pluck(:user_id)
      owners.uniq - org_user_ids
    end

    def add_owners!(quote:, owners:)
      owners.uniq.each do |user_id|
        quote.quote_owners.create!(organization:, user_id:)
      end
    end
  end
end
