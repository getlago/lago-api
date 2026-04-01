# frozen_string_literal: true

module Quotes
  class CloneService < BaseService
    class CloneError < StandardError
      attr_reader :cause, :errors

      def initialize(cause: nil, errors: {})
        @cause = cause
        @errors = errors
        super("Quote clone failed due to #{cause.class}")
      end
    end

    attr_reader :quote

    def initialize(quote:)
      @quote = quote
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.validation_failure!(errors: {quote: ["inappropriate_state"]}) unless clonable?

      result.quote = perform_clone(quote:)
      result
    rescue CloneError => e
      result.validation_failure!(errors: e.errors)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def clonable?
      return false if quote.approved?
      return false if quote.organization.quotes.where(
        sequential_id: quote.sequential_id,
        version: (quote.version + 1)..
      ).exists?

      true
    end

    def perform_clone(quote:)
      Quote.transaction do
        cloned = create_next_version(quote:)
        copy_owners!(quote:, cloned:)
        void!(quote:)

        cloned
      end
    end

    def create_next_version(quote:)
      quote.dup.tap do |cloned|
        cloned.status = :draft
        cloned.version += 1
        cloned.share_token = nil # will be generated on saving
        cloned.save!
      end
    end

    def copy_owners!(quote:, cloned:)
      quote.owner_ids.each do |user_id|
        cloned.quote_owners.create!(
          organization_id: cloned.organization_id,
          user_id: user_id
        )
      end
    end

    def void!(quote:)
      return if quote.voided?

      result = Quotes::VoidService.new(
        quote: quote,
        reason: :superseded
      ).call

      raise CloneError.new(errors: result.errors, cause: result) unless result&.success?
    end
  end
end
