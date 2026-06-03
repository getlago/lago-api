# frozen_string_literal: true

module OrderForms
  class MarkAsSignedService < BaseService
    Result = BaseResult[:order_form, :order]

    EXECUTION_MODES = %w[execute_in_lago order_only].freeze

    def initialize(order_form:, signed_document: nil, execution_mode: nil, execute_at: nil)
      @order_form = order_form
      @signed_document = signed_document
      @execution_mode = execution_mode
      @execute_at = execute_at

      super
    end

    activity_loggable(
      action: "order_form.signed",
      record: -> { order_form }
    )

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "order_form") unless order_form
      return result.not_allowed_failure!(code: "not_signable") unless order_form.generated?

      validate_execution_settings
      return result if result.failure?

      blob = signed_document_blob
      return result if result.failure?

      order_form.assign_attributes(
        status: :signed,
        signed_at: Time.current
      )

      ActiveRecord::Base.transaction do
        order_form.signed_document.attach(blob) if blob
        order_form.save!

        # TODO: Create the Order here using execution_mode/execute_at

        # TODO: Enqueue Orders::ExecuteOrderJob.perform_after_commit(result.order) when execution_mode == "execute_in_lago"
      end

      result.order_form = order_form
      result
    rescue ActiveRecord::RecordInvalid => e
      blob&.purge_later
      result.record_validation_failure!(record: e.record)
    rescue
      blob&.purge_later
      raise
    end

    private

    attr_reader :order_form, :signed_document, :execution_mode, :execute_at

    def validate_execution_settings
      validate_execution_mode
      return if result.failure?

      validate_execute_at
    end

    def validate_execution_mode
      return if execution_mode.blank? && execute_at.blank?

      if execution_mode.blank?
        return result.single_validation_failure!(field: :execution_mode, error_code: "value_is_mandatory")
      end

      return if EXECUTION_MODES.include?(execution_mode)

      result.single_validation_failure!(field: :execution_mode, error_code: "value_is_invalid")
    end

    def validate_execute_at
      return if execute_at.blank?
      return if Utils::Datetime.future_date?(execute_at)

      result.single_validation_failure!(field: :execute_at, error_code: "invalid_date")
    end

    # Validates and uploads the document OUTSIDE the transaction; returns the persisted blob (or nil).
    def signed_document_blob
      return if signed_document.blank?

      decoded = Utils::Base64File.decode(signed_document)

      unless OrderForm::SIGNED_DOCUMENT_CONTENT_TYPES.include?(decoded.content_type)
        result.single_validation_failure!(field: :signed_document, error_code: "invalid_content_type")
        return
      end

      unless decoded.io.size < OrderForm::SIGNED_DOCUMENT_MAX_SIZE
        result.single_validation_failure!(field: :signed_document, error_code: "file_too_large")
        return
      end

      ActiveStorage::Blob.create_and_upload!(
        io: decoded.io,
        filename: order_form.number,
        content_type: decoded.content_type
      )
    end
  end
end
