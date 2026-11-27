# frozen_string_literal: true

module Invoices
  class CreateCreditPurchaseService < BaseService
    Result = BaseResult[:invoice, :fee]

    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      super
    end

    def call
      return result.forbidden_failure!(code: "wallet_transaction_not_inbound") unless wallet_transaction.inbound?
      unless wallet_transaction.purchase_amount_cents.positive?
        return result.forbidden_failure!(code: "wallet_transaction_not_paid")
      end

      ActiveRecord::Base.transaction(requires_new: true) do
        wallet_transaction.lock!("FOR NO KEY UPDATE")

        if wallet_transaction.invoice_id
          result.invoice = wallet_transaction.invoice
          result.fee = result.invoice.fees.find_by(invoiceable: wallet_transaction)
          next
        end
        next result.forbidden_failure!(code: "wallet_transaction_not_pending") unless wallet_transaction.pending?

        invoice = create_generating_invoice
        fee = Fees::CreateCreditPurchaseService.call!(invoice:, wallet_transaction:).fee
        compute_amounts(invoice, fee)
        Invoices::ApplyInvoiceCustomSectionsService.call!(
          invoice:,
          resources: [Invoices::ApplyInvoiceCustomSectionsService::Resource.from(resource: contract)]
        )
        invoice.open!
        wallet_transaction.update!(invoice:)

        result.invoice = invoice
        result.fee = fee.reload
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :wallet_transaction

    def wallet
      @wallet ||= wallet_transaction.catalog_wallet
    end

    def customer
      @customer ||= wallet.customer
    end

    def contract
      @contract ||= wallet.contract
    end

    def create_generating_invoice
      Invoices::CreateGeneratingService.call!(
        customer:,
        invoice_type: :credit_purchase,
        currency: wallet.currency,
        datetime: Time.current,
        billing_entity: customer.billing_entity,
        purchase_order_number: contract.purchase_order_number
      ).invoice
    end

    def compute_amounts(invoice, fee)
      if taxes_deferred?
        invoice.fees_amount_cents = fee.amount_cents
        invoice.sub_total_excluding_taxes_amount_cents = fee.amount_cents
        invoice.sub_total_including_taxes_amount_cents = fee.amount_cents
        invoice.total_amount_cents = fee.amount_cents
      else
        Invoices::ComputeAmountsFromFees.call!(invoice:)
      end
    end

    def taxes_deferred?
      customer.tax_customer.present? || customer.vies_check_in_progress?
    end
  end
end
