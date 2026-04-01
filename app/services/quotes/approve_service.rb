# frozen_string_literal: true

module Quotes
  class ApproveService < BaseService
    attr_reader :quote

    def initialize(quote:)
      @quote = quote
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.validation_failure!(errors: {quote: ["inappropriate_state"]}) unless approvable?
      validation_errors = validate
      return result.validation_failure!(errors: {quote: validation_errors}) if validation_errors.any?

      quote.update!(
        status: :approved,
        approved_at: Time.current
      )
      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def approvable?
      quote.draft?
    end

    def validate
      []
      # TODO: payload checks
    end
  end
end
