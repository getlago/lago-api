# frozen_string_literal: true

module OrderForms
  class VoidService < BaseService
    Result = BaseResult[:order_form]

    def initialize(order_form:)
      @order_form = order_form

      super
    end

    activity_loggable(
      action: "order_form.voided",
      record: -> { order_form }
    )

    def call
      return result.not_found_failure!(resource: "order_form") unless order_form
      return result.not_allowed_failure!(code: "not_voidable") unless order_form.generated?

      order_form.assign_attributes(
        status: :voided,
        voided_at: Time.current,
        void_reason: :manual
      )

      ActiveRecord::Base.transaction do
        order_form.save!

        # TODO: Call Quotes::VoidService.call!(quote: order_form.quote, void_reason: :cascade_of_voided)

        SendWebhookJob.perform_after_commit("order_form.voided", order_form)
      end

      result.order_form = order_form
      result
    end

    private

    attr_reader :order_form
  end
end
