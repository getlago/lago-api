# frozen_string_literal: true

module Types
  module Subscriptions
    class UpdateSubscriptionInput < BaseInputObject
      description "Update Subscription input arguments"

      argument :id, ID, required: true

      argument :ending_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :invoice_custom_section, Types::InvoiceCustomSections::ReferenceInput, required: false
      argument :name, String, required: false
      argument :payment_method, Types::PaymentMethods::ReferenceInput, required: false
      argument :plan_overrides, Types::Subscriptions::PlanOverridesInput, required: false
      argument :subscription_at, GraphQL::Types::ISO8601DateTime, required: false
    end
  end
end
