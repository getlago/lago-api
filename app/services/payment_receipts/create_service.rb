# frozen_string_literal: true

module PaymentReceipts
  class CreateService < BaseService
    Result = BaseResult[:payment_receipt]

    def initialize(payment:)
      @payment = payment
      @organization = payment&.payable&.organization
      @billing_entity = payment&.payable&.billing_entity
      super
    end

    def call
      return result.not_found_failure!(resource: "payment") unless payment
      return result.forbidden_failure! unless organization.issue_receipts_enabled?
      return result if payment.payable.customer.partner_account?
      return result if payment.payable_payment_status.to_s != "succeeded"

      if payment.payment_receipt
        result.payment_receipt = payment.payment_receipt
        return result
      end

      result.payment_receipt = PaymentReceipt.create!(payment:, organization:)

      SendWebhookJob.perform_later("payment_receipt.created", result.payment_receipt)
      GeneratePdfAndNotifyJob.perform_later(payment_receipt: result.payment_receipt, email: should_deliver_email?)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :payment, :organization, :billing_entity

    def should_deliver_email?
      License.premium? && billing_entity.email_settings.include?("payment_receipt.created")
    end
  end
end
