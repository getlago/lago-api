# frozen_string_literal: true

module PaymentRequests
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      check_preconditions
      return result if result.error

      payment_request = ActiveRecord::Base.transaction do
        customer.payment_requests.create!(
          organization:,
          amount_cents: invoices.sum(:total_amount_cents),
          amount_currency: currency,
          email:,
          invoices:
        )
      end

      after_commit do
        SendWebhookJob.perform_later("payment_request.created", payment_request)

        payment_result = Payments::CreateService.call(payment_request)
        PaymentRequestMailer.with(payment_request:).requested.deliver_later unless payment_result.success?
      end

      result.payment_request = payment_request

      result
    end

    private

    attr_reader :organization, :params

    def check_preconditions
      # NOTE: Prevent creation of payment request if:
      # - the organization is not premium
      # - the customer does not exist
      # - there are no invoices
      # - the invoices are not overdue
      # - the invoices have different currencies
      # - the invoices are not ready for payment processing

      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "invoice") if invoices.empty?

      if invoices.exists?(payment_overdue: false)
        return result.not_allowed_failure!(code: "invoices_not_overdue")
      end

      if invoices.pluck(:currency).uniq.size > 1
        return result.not_allowed_failure!(code: "invoices_have_different_currencies")
      end

      if invoices.exists?(ready_for_payment_processing: false)
        result.not_allowed_failure!(code: "invoices_not_ready_for_payment_processing")
      end
    end

    def customer
      @customer ||= organization.customers.find_by(external_id: params[:external_customer_id])
    end

    def invoices
      @invoices ||= customer.invoices.where(id: params[:lago_invoice_ids])
    end

    def email
      @email ||= params[:email] || customer.email
    end

    def currency
      @currency ||= invoices.first.currency
    end
  end
end
