# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    include OrderForms::Premium

    attr_reader :organization, :customer, :subscription, :params, :owners

    Result = BaseResult[:quote]

    def initialize(organization:, customer:, subscription: nil, params: {})
      @organization = organization
      @customer = customer
      @subscription = subscription
      @params = params
      @owners = normalize_owners(owners: params[:owners])
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "organization") unless organization
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "subscription") if subscription_required? && subscription.blank?
      return result.not_found_failure!(resource: "subscription") if subscription.present? && !subscription_belongs_to_quote_scope?
      return result.forbidden_failure! unless order_forms_enabled?(organization)
      return result.single_validation_failure!(field: :owners, error_code: "invalid") unless valid_owners?

      Quote.transaction do
        quote = organization.quotes.create!(
          customer:,
          subscription:,
          **params.slice(:order_type)
        )
        initialize_version!(quote:)
        add_owners!(quote:)
        result.quote = quote
      end

      # TODO: SendWebhookJob.perform_after_commit("quote.created", quote)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def subscription_required?
      params[:order_type].to_s == "subscription_amendment"
    end

    def subscription_belongs_to_quote_scope?
      subscription.organization_id == organization.id && subscription.customer_id == customer.id
    end

    def valid_owners?
      return true if owners.blank?

      known = organization.memberships.active.where(user_id: owners).pluck(:user_id)
      (owners - known).empty?
    end

    def initialize_version!(quote:)
      QuoteVersions::CreateService.call!(
        quote: quote,
        params: params.slice(:billing_items, :content)
      )
    end

    def add_owners!(quote:)
      return if owners.blank?

      now = Time.current
      quote.quote_owners.insert_all(
        owners.map { |user_id| {organization_id: organization.id, user_id: user_id, created_at: now, updated_at: now} }
      )
    end

    def normalize_owners(owners:)
      return [] if owners.blank?
      return owners.map(&:to_s).uniq if owners.is_a?(Array)

      [owners.to_s]
    end
  end
end
