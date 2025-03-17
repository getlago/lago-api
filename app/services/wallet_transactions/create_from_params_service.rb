# frozen_string_literal: true

module WalletTransactions
  class CreateFromParamsService < ::BaseService
    Result = BaseResult[:current_wallet, :wallet_transactions]

    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      # Normalize metadata
      params[:metadata] = [] if params[:metadata] == {}
      return result unless valid? # NOTE: validator sets result.current_wallet

      wallet_transactions = []
      @source = params[:source] || :manual
      @metadata = params[:metadata] || []
      invoice_requires_successful_payment = if params.key?(:invoice_requires_successful_payment)
        ActiveModel::Type::Boolean.new.cast(params[:invoice_requires_successful_payment])
      else
        result.current_wallet.invoice_requires_successful_payment
      end
      wallet = result.current_wallet

      if params[:paid_credits]
        transaction = handle_paid_credits(
          wallet:,
          credits_amount: BigDecimal(params[:paid_credits]).floor(5),
          invoice_requires_successful_payment:
        )
        wallet_transactions << transaction
      end

      if params[:granted_credits]
        transaction = handle_granted_credits(
          wallet:,
          credits_amount: BigDecimal(params[:granted_credits]).floor(5),
          reset_consumed_credits: ActiveModel::Type::Boolean.new.cast(params[:reset_consumed_credits]),
          invoice_requires_successful_payment:
        )
        wallet_transactions << transaction
      end

      if params[:voided_credits]
        wallet_credit = WalletCredit.new(wallet:, credit_amount: BigDecimal(params[:voided_credits]).floor(5), invoiceable: false)
        void_result = WalletTransactions::VoidService.call(
          wallet:,
          wallet_credit:,
          from_source: source, metadata:
        )
        wallet_transactions << void_result.wallet_transaction
      end

      transactions = wallet_transactions.compact

      transactions.each { |wt| SendWebhookJob.perform_later("wallet_transaction.created", wt.reload) }

      result.wallet_transactions = transactions
      result
    end

    private

    attr_reader :organization, :params, :source, :metadata

    def handle_paid_credits(wallet:, credits_amount:, invoice_requires_successful_payment:)
      return if credits_amount.zero?

      wallet_credit = WalletCredit.new(wallet:, credit_amount: credits_amount)
      wallet_transaction = WalletTransactions::CreateService.call!(
        wallet:,
        wallet_credit:,
        transaction_type: :inbound,
        status: :pending,
        from_source: source,
        transaction_status: :purchased,
        invoice_requires_successful_payment:,
        metadata:
      ).wallet_transaction

      BillPaidCreditJob.perform_later(wallet_transaction, Time.current.to_i)

      wallet_transaction
    end

    def handle_granted_credits(wallet:, credits_amount:, invoice_requires_successful_payment:, reset_consumed_credits: false)
      return if credits_amount.zero?

      wallet_credit = WalletCredit.new(wallet:, credit_amount: credits_amount, invoiceable: false)
      ActiveRecord::Base.transaction do
        wallet_transaction = WalletTransactions::CreateService.call!(
          wallet:,
          wallet_credit:,
          transaction_type: :inbound,
          status: :settled,
          settled_at: Time.current,
          from_source: source,
          transaction_status: :granted,
          invoice_requires_successful_payment:,
          metadata:
        ).wallet_transaction

        Wallets::Balance::IncreaseService.new(
          wallet:,
          wallet_transaction:,
          reset_consumed_credits:
        ).call

        wallet_transaction
      end
    end

    def valid?
      WalletTransactions::ValidateService.new(
        result,
        **params.merge(organization: organization)
      ).valid?
    end
  end
end
