# frozen_string_literal: true

module X402
  module CreditPurchases
    # D4 phase 1b: from the purchase settings stored at 1a, resolve-or-create customer → subscription → wallet, then
    # grant. Under a row lock on the settlement, re-checking the link inside it, so a purchase grants once.
    # Lock order: settlement, customer (only when a subscription must be created), wallet.
    class GrantService < BaseService
      MAX_ATTEMPTS = 5

      Result = BaseResult[:settlement]

      def initialize(settlement:)
        @settlement = settlement
        super
      end

      def call
        attempts = 0

        begin
          settlement.with_lock do
            grant if settlement.wallet_transaction_id.nil?
          end
        rescue ActiveRecord::StaleObjectError
          # Wallets are optimistically locked and the refresh the previous grant queued writes the same row — the
          # retry WalletTransactions::CreateFromParamsService does. The rollback undid everything, so a retry grants once.
          attempts += 1
          raise if attempts >= MAX_ATTEMPTS

          sleep(rand(0.1..0.5))
          retry
        end

        result.settlement = settlement
        result
      end

      private

      attr_reader :settlement

      delegate :organization, :purchase_settings, :payer_address, to: :settlement

      def grant
        customer = find_or_create_customer
        subscription = find_or_create_subscription(customer)
        wallet_transaction = purchase_credits(find_or_create_wallet(customer))

        settlement.update!(customer:, subscription:, wallet_transaction:)

        # WalletTransactions::CreateService sends no webhook; CreateFromParamsService's callers expect this one (§9).
        after_commit do
          SendWebhookJob.perform_later("wallet_transaction.created", wallet_transaction)
          Utils::ActivityLog.produce(wallet_transaction, "wallet_transaction.created")
        end
      end

      # D5: one customer per normalised agent address. §16.2: agent customers never finalise zero-amount invoices.
      def find_or_create_customer
        organization.customers.find_by(x402_agent_address: payer_address) ||
          ::Customers::CreateService.call!(
            organization_id: organization.id,
            external_id: X402::ExternalIds.customer(payer_address),
            name: payer_address,
            currency: "USD",
            finalize_zero_amount_invoice: :skip,
            x402_agent_address: payer_address
          ).customer
      end

      # §16.2: one subscription per (customer, plan), found by its deterministic external id.
      def find_or_create_subscription(customer)
        plan = organization.plans.parents.find_by!(code: purchase_settings["plan_code"])
        external_id = X402::ExternalIds.subscription(payer_address, plan.code)

        customer.subscriptions.active.find_by(external_id:) ||
          ::Subscriptions::CreateService.call!(
            customer:,
            plan:,
            params: {external_id:, external_customer_id: customer.external_id, billing_time: :calendar}
          ).subscription
      end

      # D13: a new wallet takes its shape from the request — unrestricted, no limits, no expiration.
      def find_or_create_wallet(customer)
        shape = purchase_settings["wallet"]

        customer.wallets.active.find_by(code: purchase_settings["wallet_code"]) ||
          ::Wallets::CreateService.call!(
            params: {
              organization_id: organization.id,
              customer:,
              code: purchase_settings["wallet_code"],
              name: shape["name"],
              rate_amount: shape["rate_amount"],
              currency: shape["currency"],
              invoice_requires_successful_payment: false
            }
          ).wallet
      end

      # D11: the second floor, kept by invoiceable: false; then settle the purchased transaction, raising the balance.
      def purchase_credits(wallet)
        amount = BigDecimal(settlement.settled_amount_cents) / wallet.currency_for_balance.subunit_to_unit
        wallet_credit = WalletCredit.new(wallet:, credit_amount: (amount / wallet.rate_amount).floor(5), invoiceable: false)

        wallet_transaction = ::WalletTransactions::CreateService.call!(
          wallet:,
          wallet_credit:,
          transaction_type: :inbound,
          transaction_status: :purchased,
          status: :pending,
          source: :x402,
          invoice_requires_successful_payment: false,
          name: "x402 credit purchase"
        ).wallet_transaction

        ::Wallets::ApplyPaidCreditsService.call!(wallet_transaction:)
        wallet_transaction
      end
    end
  end
end
