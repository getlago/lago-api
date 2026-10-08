# frozen_string_literal: true

module X402
  module CreditPurchases
    class GrantService < BaseService
      Result = BaseResult[:settlement]

      TRANSIENT_ERRORS = [
        ActiveRecord::Deadlocked,
        ActiveRecord::LockWaitTimeout,
        ActiveRecord::RecordNotUnique,
        ActiveRecord::StaleObjectError,
        Sequenced::SequenceError
      ].freeze

      def initialize(settlement:)
        @settlement = settlement

        super
      end

      def call
        raise "#{self.class.name} must run outside a database transaction" if in_transaction?

        settlement.with_lock do
          if !settlement.credit_purchase? || !settlement.settled?
            result.single_validation_failure!(error_code: "settlement_not_grantable")
          elsif settlement.wallet_transaction_id.nil?
            grant
          end
        end

        result.settlement = settlement
        result
      rescue BaseService::FailedResult => e
        settlement.reload
        result.fail_with_error!(e)
      rescue *TRANSIENT_ERRORS => e
        settlement.reload
        result.service_failure!(code: "credit_grant_failed", message: e.message)
      end

      private

      attr_reader :settlement

      def grant
        family = X402::Network.family_of_network(settlement.network)
        customer = X402::Customers::ResolveService.call!(organization: settlement.organization, address: settlement.payer_address, family:).customer
        subscription = X402::Subscriptions::ResolveService.call!(customer:, plan_code: purchase_settings["plan_code"], family:).subscription
        wallet = X402::Wallets::ResolveService.call!(customer:, code: purchase_settings["wallet_code"], shape: purchase_settings["wallet"]).wallet
        wallet.lock!

        wallet_transaction = purchase_credits(wallet)
        BillPaidCreditJob.perform_after_commit(wallet_transaction, Time.current.to_i)
        settlement.update!(customer:, subscription:, wallet_transaction:)
      end

      def purchase_credits(wallet)
        credit_amount = (BigDecimal(settlement.settled_amount_cents) / wallet.currency_for_balance.subunit_to_unit / wallet.rate_amount).floor(5)

        wallet_transaction = ::WalletTransactions::CreateService.call!(
          wallet:,
          wallet_credit: WalletCredit.new(wallet:, credit_amount:, invoiceable: false),
          transaction_type: :inbound,
          transaction_status: :purchased,
          status: :pending,
          source: :x402,
          invoice_requires_successful_payment: false
        ).wallet_transaction

        SendWebhookJob.perform_after_commit("wallet_transaction.created", wallet_transaction)
        Utils::ActivityLog.produce_after_commit(wallet_transaction, "wallet_transaction.created")
        ::Wallets::ApplyPaidCreditsService.call!(wallet_transaction:)
        wallet_transaction
      end

      def purchase_settings
        settlement.purchase_settings
      end
    end
  end
end
