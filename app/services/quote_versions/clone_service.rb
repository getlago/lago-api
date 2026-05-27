# frozen_string_literal: true

module QuoteVersions
  class CloneService < BaseService
    include OrderForms::Premium

    class CloneError < StandardError
      attr_reader :source_result

      def initialize(source_result:)
        @source_result = source_result
        super("QuoteVersion clone failed: #{source_result&.error&.message}")
      end
    end

    attr_reader :quote_version

    Result = BaseResult[:quote_version]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless order_forms_enabled?(quote_version.organization)
      return result.forbidden_failure!(code: "inappropriate_state") unless clonable?

      cloned = QuoteVersion.transaction do
        void!(quote_version:)
        create_next_version(quote_version:)
      end

      # TODO: SendWebhookJob.perform_after_commit("quote_version.cloned", cloned)

      result.quote_version = cloned
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.forbidden_failure!(code: "active_version_exists")
    rescue CloneError => e
      result.service_failure!(code: "clone_failed", message: e.message, error: e)
    end

    private

    def clonable?
      return false if quote_version.quote.versions.where(status: :approved).exists?

      active_draft = quote_version.quote.versions.where(status: :draft).first
      active_draft.nil? || active_draft.id == quote_version.id
    end

    def create_next_version(quote_version:)
      quote_version.dup.tap do |cloned|
        cloned.status = :draft
        cloned.sequential_id = nil
        cloned.share_token = nil # regenerated on save
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

      raise CloneError.new(source_result: void_result) unless void_result&.success?
    end
  end
end
