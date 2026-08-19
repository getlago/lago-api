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
        quote_version = initialize_version!(quote:)
        add_owners!(quote:)

        SendWebhookJob.perform_after_commit("quote.created", quote_version)
        # The webhook needs the version for its payload; the activity log records the quote, whose
        # number, order type and owners are what a reader looks for on a creation entry.
        Utils::ActivityLog.produce_after_commit(quote, "quote.created")

        result.quote = quote
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
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
        params: params.slice(:billing_items, :content, :billing_entity_id).merge(currency: deal_currency)
      ).quote_version
    end

    # The deal currency follows the billing object when there is one, and only then the customer's
    # own default. It stays editable on the draft through QuoteVersions::UpdateService.
    def deal_currency
      return subscription.plan_amount_currency if subscription

      customer.currency.presence || issuing_billing_entity.default_currency
    end

    # The entity the deal is issued by, which is the one whose default currency the quote should
    # fall back to. An unknown id is left to the version validator to report, so the fallback simply
    # keeps the customer's own entity here.
    def issuing_billing_entity
      organization.billing_entities.find_by(id: params[:billing_entity_id]) || customer.billing_entity
    end

    def add_owners!(quote:)
      return if owners.blank?

      owners.each do |user_id|
        quote.quote_owners.create!(organization:, user_id:)
      end
    end

    def normalize_owners(owners:)
      return [] if owners.blank?
      return owners.map(&:to_s).uniq if owners.is_a?(Array)

      [owners.to_s]
    end
  end
end
