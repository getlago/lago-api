# frozen_string_literal: true

module Quotes
  class DestroyService < BaseService
    attr_reader :quote

    def initialize(quote:)
      @quote = quote
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.validation_failure!(errors: {quote: ["inappropriate_state"]}) unless destroyable?

      quote.destroy!
      result.quote = quote
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def destroyable?
      return false if quote.approved?
      return false if quote.order_form.present?
      return false if quote.order.present?
      true
    end
  end
end
