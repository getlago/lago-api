# frozen_string_literal: true

module WalletTransactions
  # Fails a paid top-up that nobody is paying, so it stops counting in the wallet's threshold
  # check and blocking the automatic top-up.
  #
  # Only top-ups gated on a successful payment: their invoice stays open, which is invisible,
  # so nothing else can pay, void or clear it. Other top-ups have a finalized invoice that the
  # customer manages, and voiding it fails the top-up (Invoices::VoidService).
  #
  # Before failing it, everything the end customer could still use to pay it is closed (the
  # 3DS challenge, the bank transfer, the payment link): a late payment would otherwise take
  # money for a failed top-up. A payment that is actually moving (a card charge processing,
  # a direct debit settling) is left to finish.
  class ExpirePendingService < BaseService
    Result = BaseResult[:wallet_transaction]

    TIMEOUT = 1.hour
    # The provider never expires a bank transfer waiting for its wire
    BANK_TRANSFER_TIMEOUT = 7.days

    OPEN_PAYMENT_STATUSES = %w[pending processing].freeze

    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      super
    end

    def call
      result.wallet_transaction = wallet_transaction

      return result unless expirable?

      # Not open yet, still generating: its payment has not started
      return result unless invoice&.open?
      # A merchant recorded part of the amount: they are collecting it, so its payment paths stay open
      return result if partly_paid?

      payment = open_payment
      return result if payment && !stop_payment(payment)

      PaymentIntents::ExpireService.call!(invoice:)

      ActiveRecord::Base.transaction do
        # with_lock reloads the invoice, so a payment recorded since it was read is seen here.
        # A payment that lands after the commit still marks the invoice paid, and
        # Invoices::PrepaidCreditJob then settles the failed top-up: the customer gets the credits.
        closed = invoice.with_lock do
          next false unless invoice.open? && !invoice.payment_succeeded?
          # Recorded meanwhile: closing would bury that money on an invisible invoice that can no longer be paid
          next false if partly_paid?

          invoice.closed!
          true
        end

        WalletTransactions::MarkAsFailedService.call!(wallet_transaction:) if closed
      end

      result
    end

    private

    attr_reader :wallet_transaction

    def expirable?
      wallet_transaction.inbound? &&
        wallet_transaction.pending? &&
        wallet_transaction.invoice_requires_successful_payment? &&
        wallet_transaction.created_at <= TIMEOUT.ago
    end

    def invoice
      @invoice ||= wallet_transaction.invoice
    end

    def partly_paid?
      invoice.total_paid_amount_cents.positive?
    end

    # A partial unique index allows at most one provider payment in (pending, processing) per invoice
    def open_payment
      invoice.payments.payment_type_provider.find_by(payable_payment_status: OPEN_PAYMENT_STATUSES)
    end

    # Returns whether the payment can no longer pay the invoice
    def stop_payment(payment)
      # Other providers do not wait on the end customer the same way (GoCardless is a direct
      # debit, already moving), and their webhooks settle the payment: leave it to them
      return false unless payment.payment_provider_type == "stripe"
      return false if payment.provider_payment_id.blank?

      intent = stripe_intent(payment)
      return false unless intent

      case intent.status
      when "canceled"
        # Over at the provider, and its webhook never reached us
        payment.update!(
          status: intent.status,
          payable_payment_status: payment.payment_provider.determine_payment_status(intent.status)
        )
        true
      when "requires_action"
        return false if waiting_for_wire?(intent)

        cancel(payment)
      when "requires_payment_method", "requires_confirmation"
        cancel(payment)
      else
        # processing, requires_capture: money is moving. succeeded: its webhook settles the top-up
        false
      end
    end

    def waiting_for_wire?(intent)
      intent.payment_method_type == "customer_balance" &&
        wallet_transaction.created_at > BANK_TRANSFER_TIMEOUT.ago
    end

    # The provider refuses to cancel an intent that moved on meanwhile (paid, processing), and
    # leaves the payment as it was: it is then still open and the top-up is not failed
    def cancel(payment)
      PaymentProviders::CancelPaymentService.call!(payment:)

      OPEN_PAYMENT_STATUSES.exclude?(payment.reload.payable_payment_status)
    end

    def stripe_intent(payment)
      PaymentProviders::Stripe::Payments::RetrieveService.call!(payment:)
    rescue ::Stripe::AuthenticationError, ::Stripe::PermissionError, ::Stripe::InvalidRequestError => e
      Rails.logger.warn(
        "WalletTransactions::ExpirePendingService: cannot read intent " \
        "#{payment.provider_payment_id} for payment #{payment.id}: #{e.class.name}"
      )
      nil
    end
  end
end
