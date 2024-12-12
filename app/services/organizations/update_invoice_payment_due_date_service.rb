# frozen_string_literal: true

module Organizations
  class UpdateInvoicePaymentDueDateService < BaseService
    def initialize(organization:, net_payment_term:)
      @organization = organization
      @net_payment_term = net_payment_term
      super
    end

    def call
      ActiveRecord::Base.transaction do
        # NOTE: Update payment_due_date if net_payment_term changed
        #
        if organization.net_payment_term != net_payment_term
          organization.net_payment_term = net_payment_term

          organization.invoices.draft.each do |invoice|
            invoice.update!(payment_due_date: invoice_payment_due_date(invoice))
          end
        end

        result.organization = organization
        result
      end
    end

    private

    attr_reader :organization, :net_payment_term

    def invoice_payment_due_date(invoice)
      invoice.issuing_date + net_payment_term.days
    end
  end
end
