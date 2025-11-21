# frozen_string_literal: true

module BillingEntities
  class UpdateInvoiceIssuingDateSettingsService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(billing_entity:, params:)
      @billing_entity = billing_entity
      @params = params
      @old_issuing_date_settings = {
        invoice_grace_period: billing_entity.invoice_grace_period,
        subscription_invoice_issuing_date_anchor: billing_entity.subscription_invoice_issuing_date_anchor,
        subscription_invoice_issuing_date_adjustment: billing_entity.subscription_invoice_issuing_date_adjustment
      }
      super
    end

    def call
      set_issuing_date_settings

      if billing_entity.changed? && billing_entity.save!
        Invoices::UpdateAllInvoiceIssuingDateFromBillingEntityJob.perform_later(billing_entity, old_issuing_date_settings)
      end

      result.billing_entity = billing_entity
      result
    end

    private

    attr_reader :billing_entity, :params, :old_issuing_date_settings

    def set_issuing_date_settings
      billing_configuration = params[:billing_configuration]&.to_h || {}

      if billing_configuration.key?(:subscription_invoice_issuing_date_anchor)
        billing_entity.subscription_invoice_issuing_date_anchor = billing_configuration[:subscription_invoice_issuing_date_anchor]
      end

      if billing_configuration.key?(:subscription_invoice_issuing_date_adjustment)
        billing_entity.subscription_invoice_issuing_date_adjustment = billing_configuration[:subscription_invoice_issuing_date_adjustment]
      end

      if License.premium? && billing_configuration.key?(:invoice_grace_period)
        billing_entity.invoice_grace_period = billing_configuration[:invoice_grace_period]
      end
    end
  end
end
