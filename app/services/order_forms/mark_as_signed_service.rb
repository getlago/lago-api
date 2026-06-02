# frozen_string_literal: true

module OrderForms
  class MarkAsSignedService < BaseService
    Result = BaseResult[:order_form, :order]

    def initialize(order_form:, signed_document: nil)
      @order_form = order_form
      @signed_document = signed_document

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

      order_form.assign_attributes(
        status: :signed,
        signed_at: Time.current
      )

      ActiveRecord::Base.transaction do
        attach_signed_document
        order_form.save!

        # TODO: Create the Order here

        # TODO: Enqueue Orders::ExecuteOrderJob.perform_after_commit(result.order) when auto_execute is true
      end

      result.order_form = order_form
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :order_form, :signed_document

    def attach_signed_document
      return if signed_document.blank?

      base64_data = signed_document.split(",")
      decoded = Base64.decode64(base64_data.second)
      content_type = base64_data.first.split(";").first.split(":").second

      order_form.signed_document.attach(
        io: StringIO.new(decoded),
        filename: "#{order_form.number}.pdf",
        content_type:
      )
    end

    def quote
      @quote ||= order_form.quote
    end
  end
end
