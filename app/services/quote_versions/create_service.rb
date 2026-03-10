# frozen_string_literal: true

module QuoteVersions
  class CreateService < BaseService
    attr_reader :organization, :quote, :params

    Result = BaseResult[:quote_version]

    def initialize(organization:, quote:, params: {})
      @organization = organization
      @quote = quote
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "organization") unless organization
      return result.not_found_failure!(resource: "quote") unless quote
      return result.forbidden_failure! unless organization.feature_flag_enabled?(:order_forms)

      create_params = params.slice(
        :billing_items,
        :content
      )

      quote_version = quote.versions.create!(
        organization:,
        **create_params
      )

      result.quote_version = quote_version

      # TODO: SendWebhookJob.perform_after_commit("quote_version.created", quote_version)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::ActiveRecordError => e
      result.service_failure!(code: "create_failed", message: e.message, error: e)
    end
  end
end
