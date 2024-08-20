# frozen_string_literal: true

module PaymentRequests
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      ActiveRecord::Base.transaction do
        # NOTE: Create payable group for the overdue invoices
        payable_group = customer.payable_groups.create!(organization:)
        invoices.each { |i| i.update!(payable_group:) }

        # TODO: Create payment request for the payable group

        # TODO: Send payment_request.created webhook

        # TODO: When payment provider is set: Create payment intent for the overdue invoices
        # TODO: When payment provider is not set: Send email to the customer

        # result.payment_request = payment_request
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
  end
end
