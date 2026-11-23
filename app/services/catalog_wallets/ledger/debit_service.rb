# frozen_string_literal: true

module CatalogWallets
  module Ledger
    class DebitService < BaseService
      REASONS = %w[invoice_application void].freeze

      Result = BaseResult[:wallet_transaction]

      def initialize(wallet:, reason:, consumptions:, invoice: nil)
        @wallet = wallet
        @reason = reason.to_s
        @consumptions = consumptions
        @invoice = invoice
        super

        check_arguments!
      end

      def call
        with_ledger_lock(wallet) do
          # Under the lock, so a retried caller sees the debit it already committed and doesn't spend the credit twice.
          if (paid = previous_invoice_application)
            result.wallet_transaction = paid
            next
          end

          entries = wallet.transactions.where(id: debits.keys).lock("FOR NO KEY UPDATE").order(:id).index_by(&:id)

          unless debits.keys.all? { entries[it]&.inbound? && entries[it].settled? }
            next result.forbidden_failure!(code: "wallet_transaction_not_spendable")
          end

          if debits.any? { |id, amount_cents| amount_cents > entries[id].remaining_credit_amount_cents }
            next result.single_validation_failure!(field: :credit_amount, error_code: "exceeds_remaining_credit")
          end

          result.wallet_transaction = create_outbound_transaction
          create_consumptions(result.wallet_transaction, entries)
          debits.each do |id, amount_cents|
            entries[id].update!(remaining_credit_amount_cents: entries[id].remaining_credit_amount_cents - amount_cents)
          end
          move_balance(wallet, by: -debits.values.sum)
        end

        result
      end

      private

      attr_reader :wallet, :reason, :consumptions, :invoice

      def check_arguments!
        raise ArgumentError, "Invalid reason: #{reason}. Valid reasons are: #{REASONS.join(", ")}" unless REASONS.include?(reason)
        raise ArgumentError, "A debit needs at least one consumption" if consumptions.empty?

        unless consumptions.all? { it[:inbound_transaction].is_a?(CatalogWalletTransaction) }
          raise ArgumentError, "Each consumption needs an inbound transaction"
        end

        unless consumptions.all? { it[:credit_amount_cents].is_a?(Integer) && it[:credit_amount_cents].positive? }
          raise ArgumentError, "Each consumption needs a positive amount in cents"
        end

        if consumptions.uniq { [it[:inbound_transaction].id, it[:fee]&.id] }.size != consumptions.size
          raise ArgumentError, "An entry can pay a fee only once"
        end

        (reason == "void") ? check_void_arguments! : check_invoice_application_arguments!
      end

      def check_void_arguments!
        raise ArgumentError, "A void takes no invoice" if invoice
        raise ArgumentError, "A void takes no fee" if consumptions.any? { it[:fee] }
      end

      def check_invoice_application_arguments!
        raise ArgumentError, "An invoice application needs an invoice" if invoice.nil?
        raise ArgumentError, "The invoice must belong to the wallet's customer" if invoice.customer_id != wallet.customer_id
        raise ArgumentError, "Each fee must belong to the invoice" unless consumptions.all? { it[:fee].nil? || it[:fee].invoice_id == invoice.id }
      end

      def previous_invoice_application
        return unless reason == "invoice_application"

        wallet.transactions.outbound.invoice_application.where(invoice:).order(:created_at).first
      end

      def debits
        @debits ||= consumptions
          .group_by { it[:inbound_transaction].id }
          .transform_values { |rows| rows.sum { it[:credit_amount_cents] } }
      end

      def create_outbound_transaction
        wallet.transactions.create!(
          organization: wallet.organization,
          direction: :outbound,
          status: :settled,
          settled_at: Time.current,
          reason:,
          invoice:,
          credit_amount_cents: debits.values.sum
        )
      end

      def create_consumptions(outbound_transaction, entries)
        consumptions.each do |consumption|
          CatalogWalletConsumption.create!(
            organization: wallet.organization,
            outbound_transaction:,
            inbound_transaction: entries.fetch(consumption[:inbound_transaction].id),
            fee: consumption[:fee],
            credit_amount_cents: consumption[:credit_amount_cents]
          )
        end
      end
    end
  end
end
