# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      result.invoice = invoice

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        invoice.void!

        flag_lifetime_usage if invoice.subscription?
      end

      invoice.credits.each do |credit|
        res = CreditNotes::RecreditService.call(credit:)
        Rails.logger.warn("Recrediting credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
      end

      invoice.wallet_transactions.each do |wallet_transaction|
        res = WalletTransactions::RecreditService.call(wallet_transaction:)

        unless res.success?
          Rails.logger.warn("Recrediting wallet transaction #{wallet_transaction.id} failed for invoice #{invoice.id}")
        end
      end

      SendWebhookJob.perform_later('invoice.voided', result.invoice)

      result
    rescue AASM::InvalidTransition => _e
      result.not_allowed_failure!(code: 'not_voidable')
    end

    private

    attr_reader :invoice

    def flag_lifetime_usage
      invoice.subscriptions.each do |subscription|
        lifetime_usage = subscription.lifetime_usage
        lifetime_usage ||= subscription.build_lifetime_usage(organization: subscription.organization)
        lifetime_usage.recalculate_invoiced_usage = true
        lifetime_usage.save!
      end
    end
  end
end
