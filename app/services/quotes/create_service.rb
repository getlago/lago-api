# frozen_string_literal: true

module Quotes
  class CreateService < BaseService
    class CreateError < StandardError
      attr_reader :cause, :error

      def initialize(cause: nil, error: nil)
        @cause = cause
        @error = error
        super("Quote creation failed due to #{cause.class}")
      end
    end

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
      return result.forbidden_failure! unless organization.feature_flag_enabled?(:order_forms)
      return result.validation_failure!(errors: {quotes: ["invalid_owner"]}) unless check_owners(owners:)

      quote_create_params = params.slice(
        :order_type
      )
      quote_version_create_params = params.slice(
        :billing_items,
        :content
      )

      Quote.transaction do
        quote = organization.quotes.create!(
          customer:,
          subscription:,
          **quote_create_params
        )
        initialize_version!(
          quote:,
          version_params: quote_version_create_params
        )
        add_owners!(quote:, owners:)
        result.quote = quote
      end

      # TODO: SendWebhookJob.perform_after_commit("quote.created", quote)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue CreateError, ActiveRecord::ActiveRecordError => e
      result.service_failure!(code: "create_failed", message: e.message, error: e)
    end

    private

    def subscription_required?
      params[:order_type].to_s == "subscription_amendment"
    end

    def check_owners(owners:)
      return true if owners.blank?

      valid_owners = organization.memberships.active.pluck(:user_id)
      invalid_owners = owners - valid_owners
      return false if invalid_owners.any?

      true
    end

    def initialize_version!(quote:, version_params: {})
      create_result = QuoteVersions::CreateService.new(
        organization: quote.organization,
        quote: quote,
        params: version_params
      ).call

      raise CreateError.new(error: create_result.error, cause: create_result) unless create_result&.success?
    end

    def add_owners!(quote:, owners:)
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
