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
        # NOTE: Create payable group for the overdue invoices
        payable_group = customer.payable_groups.create!(organization:)
        invoices.update_all(payable_group_id: payable_group.id) # rubocop:disable Rails/SkipsModelValidations

        # NOTE: Create payment request for the payable group
        payment_request = payable_group.payment_requests.create!(
          organization:,
          customer:,
          amount_currency: invoices.first.currency,
          email:
        )

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
