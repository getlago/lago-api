# frozen_string_literal: true

module OrderForms
  class MarkAsSignedService < BaseService
    include OrderForms::Premium

    Result = BaseResult[:order_form, :order]

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
      return result.not_found_failure!(resource: "order_form") unless order_form
      return result.forbidden_failure! unless order_forms_enabled?(order_form.organization)
      return result.single_validation_failure!(field: :status, error_code: "not_signable") unless order_form.generated?

      validate_execution_settings
      return result if result.failure?

      attachment = signed_document_attachment
      return result if result.failure?

      order_form.assign_attributes(
        status: :signed,
        signed_at: Time.current
      )

      ActiveRecord::Base.transaction do
        order_form.signed_document.attach(attachment) if attachment
        order_form.save!

        result.order = Order.create!(
          organization: order_form.organization,
          customer: order_form.customer,
          order_form:,
          execution_mode:,
          execute_at:
        )

        # TODO: Enqueue Orders::ExecuteOrderJob.perform_after_commit(result.order) when execution_mode == "execute_in_lago"
      end

      result.order_form = order_form
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :order_form_id, error_code: "value_already_exist")
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

      return if Order::EXECUTION_MODES.value?(execution_mode)

      result.single_validation_failure!(field: :execution_mode, error_code: "value_is_invalid")
    end

    def validate_execute_at
      return if execute_at.blank?
      return if Utils::Datetime.future_date?(execute_at)

      result.single_validation_failure!(field: :execute_at, error_code: "invalid_date")
    end

    def signed_document_attachment
      return if signed_document.blank?

      decoded = Utils::Base64File.decode(signed_document)

      if decoded.nil?
        result.single_validation_failure!(field: :signed_document, error_code: "invalid_format")
        return
      end

      {
        io: decoded.io,
        filename: order_form.number,
        content_type: decoded.content_type
      }
    end
  end
end
