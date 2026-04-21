# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    Result = BaseResult[:quote]

    def initialize(organization:, customer:, subscription: nil, params: {})
      @organization = organization
      @customer = customer
      @subscription = subscription
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "organization") unless organization
      return result.not_found_failure!(resource: "customer") unless customer
      return result.forbidden_failure! unless organization.feature_flag_enabled?(:quote)

      if params[:owners].present?
        invalid_ids = invalid_owner_ids(params[:owners])
        if invalid_ids.any?
          return result.single_validation_failure!(error_code: "not_found", field: :owners)
        end
      end

      quote = Quote.transaction do
        quote = organization.quotes.create!(
          customer:,
          subscription:,
          order_type: params[:order_type]
        )
        add_owners!(quote:, owners: params[:owners]) if params[:owners].present?
        quote
      end

      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :customer, :subscription, :params

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
