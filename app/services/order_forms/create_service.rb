# frozen_string_literal: true

module OrderForms
  class CreateService < BaseService
    attr_reader :organization, :customer, :params

    def initialize(organization:, customer:, params:)
      @organization = organization
      @customer = customer
      @params = params

      super
    end

    def call
      create_params = params.slice(
        :auto_execute,
        :backdated_billing,
        :order_only
      )
      order_form = organization.order_forms.new(
        customer: @customer,
        **create_params
      )
      order_form.save!
      result.order_form = order_form
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
