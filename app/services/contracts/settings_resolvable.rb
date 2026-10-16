# frozen_string_literal: true

module Contracts
  # Shared resolution, validation and assignment of a contract's billing entity,
  # invoicing and payment settings for the create and update services. Expects
  # the host to expose `organization`, `customer`, `params` and `result`.
  module SettingsResolvable
    extend ActiveSupport::Concern

    private

    # Explicit billing-entity override; nil (no id) inherits the customer's.
    def billing_entity
      return @billing_entity if defined?(@billing_entity)

      @billing_entity = params[:billing_entity_id].present? ? organization.billing_entities.find_by(id: params[:billing_entity_id]) : nil
    end

    # Nested payment-method reference input {payment_method_id, payment_method_type}.
    def payment_method_params
      params[:payment_method] || {}
    end

    # Payment methods are scoped to the contract's customer.
    def payment_method
      return @payment_method if defined?(@payment_method)

      @payment_method = payment_method_params[:payment_method_id].present? ? customer.payment_methods.find_by(id: payment_method_params[:payment_method_id]) : nil
    end

    # Validates the references and their combination; returns a failed result to
    # bail on, or nil when they are valid. Sets the resolved payment method on
    # the result for PaymentMethods::ValidateService (manual + a concrete method
    # is contradictory).
    def settings_references_failure
      return result.not_found_failure!(resource: "billing_entity") if params[:billing_entity_id].present? && billing_entity.nil?
      return result.not_found_failure!(resource: "payment_method") if payment_method_params[:payment_method_id].present? && payment_method.nil?

      result.payment_method = payment_method
      return result unless PaymentMethods::ValidateService.new(result, payment_method: params[:payment_method]).valid?

      nil
    end

    # Applies the provided settings to a contract. Omitted values keep the
    # record's current value (a new record already carries the NOT NULL column
    # defaults); an explicit null clears the billing-entity override and the
    # purchase order number.
    def apply_settings(contract)
      contract.billing_entity = billing_entity if params.key?(:billing_entity_id)
      contract.consolidate_invoice = params[:consolidate_invoice] unless params[:consolidate_invoice].nil?
      contract.purchase_order_number = params[:purchase_order_number] if params.key?(:purchase_order_number)
      contract.payment_method = payment_method if payment_method_params.key?(:payment_method_id)
      contract.payment_method_type = payment_method_params[:payment_method_type] if payment_method_params[:payment_method_type].present?
    end
  end
end
