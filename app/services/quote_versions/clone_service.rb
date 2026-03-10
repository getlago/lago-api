# frozen_string_literal: true

module QuoteVersions
  class CloneService < BaseService
    class CloneError < StandardError
      attr_reader :cause, :error

      def initialize(cause: nil, error: nil)
        @cause = cause
        @error = error
        super("QuoteVersion clone failed due to #{cause.class}")
      end
    end

    attr_reader :quote_version

    Result = BaseResult[:quote_version]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless quote_version.organization.feature_flag_enabled?(:order_forms)
      return result.not_allowed_failure!(code: "inappropriate_state") unless clonable?

      cloned = QuoteVersion.transaction do
        void!(quote_version:)
        create_next_version(quote_version:)
      end

      # TODO: SendWebhookJob.perform_after_commit("quote_version.cloned", cloned)

      result.quote_version = cloned
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue CloneError, ActiveRecord::ActiveRecordError => e
      result.service_failure!(code: "clone_failed", message: e.message, error: e)
    end

    private

    def clonable?
      return false if quote_version.approved?

      true
    end

    def create_next_version(quote_version:)
      quote_version.dup.tap do |cloned|
        cloned.status = :draft
        cloned.sequential_id = nil
        cloned.share_token = nil # will be generated on saving
        cloned.void_reason = nil
        cloned.voided_at = nil
        cloned.approved_at = nil
        cloned.save!
      end
    end

    def void!(quote_version:)
      return if quote_version.voided?

      void_result = QuoteVersions::VoidService.new(
        quote_version: quote_version,
        reason: :superseded
      ).call

      raise CloneError.new(error: void_result.error, cause: void_result) unless void_result&.success?
    end
  end
end
