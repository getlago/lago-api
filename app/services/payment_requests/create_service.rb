# frozen_string_literal: true

module PaymentRequests
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      unless License.premium? && organization.premium_integrations.include?("dunning")
        return result.not_allowed_failure!(code: "premium_addon_feature_missing")
      end

      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "invoice") if invoices.empty?

      if invoices.exists?(payment_overdue: false)
        return result.not_allowed_failure!(code: "invoices_not_overdue")
      end

      ActiveRecord::Base.transaction do
        # NOTE: Create payment request for the payable group
        payment_request = customer.payment_requests.create!(
          organization:,
          amount_cents: invoices.sum(:total_amount_cents),
          amount_currency: invoices.first.currency,
          email:
        )
        invoices.each { |i| payment_request.applied_invoices.create!(invoice: i) }

        # NOTE: Send payment_request.created webhook
        SendWebhookJob.perform_later("payment_request.created", payment_request)

        # TODO: When payment provider is set: Create payment intent for the overdue invoices
        # TODO: When payment provider is not set: Send email to the customer

        result.payment_request = payment_request
      end

      result
    end

    private

    attr_reader :organization, :params

    def customer
      @customer ||= organization.customers.find_by(external_id: params[:external_customer_id])
    end

    def invoices
      @invoices ||= customer.invoices.where(id: params[:lago_invoice_ids])
    end

    def email
      @email ||= params[:email] || customer.email
    end
  end
end
