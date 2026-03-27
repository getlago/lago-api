# frozen_string_literal: true

module Quotes
  class DestroyService < BaseService
    Result = BaseResult[:quote]

    def initialize(quote:)
      @quote = quote

      super
    end

    def call
      return result.not_found_failure!(resource: "quote") unless quote
      return result.not_allowed_failure!(code: "quote_not_draft") unless quote.draft?
      return result.not_allowed_failure!(code: "quote_not_deletable") unless quote.version == 1

      quote.destroy!

      result.quote = quote
      result
    end

    private

    attr_reader :quote
  end
end
