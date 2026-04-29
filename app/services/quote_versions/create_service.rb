# frozen_string_literal: true

module QuoteVersions
  class CreateService < BaseService
    attr_reader :quote, :params

    Result = BaseResult[:quote_version]

    def initialize(quote:, params: {})
      @quote = quote
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.forbidden_failure! unless quote.organization.feature_flag_enabled?(:order_forms)

      quote_version = quote.versions.create!(
        organization: quote.organization,
        **params.slice(:billing_items, :content)
      )

      result.quote_version = quote_version

      # TODO: SendWebhookJob.perform_after_commit("quote_version.created", quote_version)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
