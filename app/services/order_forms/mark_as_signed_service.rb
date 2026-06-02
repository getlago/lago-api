# frozen_string_literal: true

module OrderForms
  class MarkAsSignedService < BaseService
    Result = BaseResult[:order_form, :order]

    EXECUTION_MODES = %w[execute_in_lago order_only].freeze

    def initialize(order_form:, signed_document: nil, execution_mode: nil, execution_date: nil)
      @order_form = order_form
      @signed_document = signed_document
      @execution_mode = execution_mode
      @execution_date = execution_date

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

      if execution_mode.present? && EXECUTION_MODES.exclude?(execution_mode)
        return result.single_validation_failure!(field: :execution_mode, error_code: "value_is_invalid")
      end

      if execution_date.present? && !Utils::Datetime.valid_format?(execution_date, format: :any)
        return result.single_validation_failure!(field: :execution_date, error_code: "invalid_date")
      end

      order_form.assign_attributes(
        status: :signed,
        signed_at: Time.current
      )

      ActiveRecord::Base.transaction do
        attach_signed_document
        order_form.save!

        # TODO: Create the Order here using execution_mode/execution_date

        # TODO: Enqueue Orders::ExecuteOrderJob.perform_after_commit(result.order) when execution_mode == "execute_in_lago"
      end

      result.order_form = order_form
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :order_form, :signed_document, :execution_mode, :execution_date

    def attach_signed_document
      return if signed_document.blank?

      decoded = Utils::Base64File.decode(signed_document)
      order_form.signed_document.attach(
        io: decoded.io,
        filename: "#{order_form.number}.pdf",
        content_type: decoded.content_type
      )
    end

    def quote
      @quote ||= order_form.quote
    end
  end
end
