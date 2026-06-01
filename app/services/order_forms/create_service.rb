# frozen_string_literal: true

module OrderForms
  class CreateService < BaseService
    include OrderForms::Premium

    Result = BaseResult[:order_form]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless order_forms_enabled?(quote_version.organization)
      return result.not_allowed_failure!(code: "quote_version_not_approved") unless quote_version.approved?

      order_form = OrderForm.create!(
        organization: quote_version.organization,
        customer: quote_version.quote.customer,
        quote_version:,
        status: :generated
      )

      result.order_form = order_form
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :quote_version
  end
end
