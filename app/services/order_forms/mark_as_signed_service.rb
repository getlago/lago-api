# frozen_string_literal: true

module OrderForms
  class MarkAsSignedService < BaseService
    Result = BaseResult[:order_form, :order]

    def initialize(order_form:, user:)
      @order_form = order_form
      @user = user

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
        signed_at: Time.current,
        signed_by_user_id: user.id
      )

      ActiveRecord::Base.transaction do
        order_form.save!

        # TODO: Create the Order here

        # TODO: Enqueue Orders::ExecuteOrderJob.perform_after_commit(result.order) when auto_execute is true
      end

      result.order_form = order_form
      result
    end

    private

    attr_reader :order_form, :user

    def quote
      @quote ||= order_form.quote
    end
  end
end
