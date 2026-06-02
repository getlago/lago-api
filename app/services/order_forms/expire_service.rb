# frozen_string_literal: true

module OrderForms
  class ExpireService < BaseService
    include OrderForms::Premium

    Result = BaseResult[:order_form]

    def initialize(order_form:)
      @order_form = order_form

      super
    end

    def call
      return result.not_found_failure!(resource: "order_form") unless order_form
      return result.forbidden_failure! unless order_forms_enabled?(order_form.organization)

      return result.not_allowed_failure!(code: "order_form_is_voided") if order_form.voided?
      return result.not_allowed_failure!(code: "order_form_is_signed") if order_form.signed?

      if order_form.expired?
        result.order_form = order_form
        return result
      end

      order_form.assign_attributes(status: :expired, voided_at: Time.current, void_reason: :expired)

      ActiveRecord::Base.transaction do
        order_form.save!

        QuoteVersions::VoidService.call!(quote_version: order_form.quote_version, reason: :cascade_of_expired)
      end

      result.order_form = order_form
      result
    end

    private

    attr_reader :order_form
  end
end
