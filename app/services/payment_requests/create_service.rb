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

      ActiveRecord::Base.transaction do
        # NOTE: Create payment request for the payable group
        payment_request = customer.payment_requests.create!(
          organization:,
          amount_cents: invoices.sum(:total_amount_cents),
          amount_currency: currency,
          email:,
          invoices:
        )

        # NOTE: Send payment_request.created webhook
        SendWebhookJob.perform_later("payment_request.created", payment_request)

        Payments::CreateService.call(payment_request)

        # TODO: When payment provider is not set: Send email to the customer

        result.payment_request = payment_request
      end

      result
    end

    private

    attr_reader :organization, :params

    def check_preconditions
      # NOTE: Prevent creation of payment request if:
      # - the organization does not have the premium dunning integration
      # - the customer does not exist
      # - there are no invoices
      # - the invoices are not overdue
      # - the invoices have different currencies
      # - the invoices are not ready for payment processing

      unless License.premium? && organization.premium_integrations.include?("dunning")
        return result.not_allowed_failure!(code: "premium_addon_feature_missing")
      end

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
