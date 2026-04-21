# frozen_string_literal: true

module Quotes
  class CloneService < BaseService
    Result = BaseResult[:quote]

    def initialize(quote:)
      @quote = quote
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote") unless quote
      return result.forbidden_failure! unless quote.organization.feature_flag_enabled?(:quote)

      cloned = Quote.transaction do
        new_quote = create_next_version(quote:)
        copy_owners!(source: quote, destination: new_quote)
        supersede_active_prior_versions!(new_quote)
        new_quote
      end

      result.quote = cloned
      result
    rescue ActiveRecord::RecordNotUnique
      result.service_failure!(code: "concurrent_clone", message: "Another clone is already in progress for this quote")
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :quote

    def create_next_version(quote:)
      max_version = Quote
        .where(organization_id: quote.organization_id, sequential_id: quote.sequential_id)
        .maximum(:version)

      quote.dup.tap do |cloned|
        cloned.status = :draft
        cloned.version = max_version + 1
        cloned.voided_at = nil
        cloned.void_reason = nil
        cloned.save!
      end
    end

    def copy_owners!(source:, destination:)
      source.owner_ids.each do |user_id|
        destination.quote_owners.create!(
          organization_id: destination.organization_id,
          user_id: user_id
        )
      end
    end

    def supersede_active_prior_versions!(new_quote)
      Quote
        .where(organization_id: new_quote.organization_id, sequential_id: new_quote.sequential_id)
        .where("version < ?", new_quote.version)
        .where.not(status: :voided)
        .find_each do |prior|
          Quotes::VoidService.call(quote: prior, reason: :superseded).raise_if_error!
        end
    end
  end
end
