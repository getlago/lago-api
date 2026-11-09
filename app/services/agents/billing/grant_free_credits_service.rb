# frozen_string_literal: true

module Agents
  module Billing
    # A claimed agent collects the free credits its plan offers. One grant per owner mailbox and storefront,
    # whatever the number of agents that owner claims there: the unique index on the grants decides.
    class GrantFreeCreditsService < BaseService
      Result = BaseResult[:grant, :replayed]

      def initialize(storefront:, registration:)
        @storefront = storefront
        @registration = registration

        super
      end

      def call
        return result.single_validation_failure!(error_code: "enrollment_required") unless wallet && subscription

        # One lock for the replay check and the grant, so the same agent asking twice at once is served once.
        registration.with_lock do
          result.grant = Agents::FreeCreditGrant.find_by(registration:)
          if result.grant
            result.replayed = true
            next
          end

          next result.single_validation_failure!(error_code: "claim_required") unless email_hash
          next result.single_validation_failure!(error_code: "free_credits_not_offered") unless amount_cents.positive?

          create_grant
        end

        result
      rescue ActiveRecord::RecordNotUnique => e
        raise unless violated_unique_index(e) == Agents::FreeCreditGrant::UNIQUE_INDEX

        # Another agent of the same owner was served first.
        result.single_validation_failure!(error_code: "free_credits_already_granted")
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :storefront, :registration

      def wallet
        @wallet ||= registration.wallet
      end

      def subscription
        @subscription ||= registration.subscription
      end

      def email_hash
        @email_hash ||= registration.claims.verified.pick(:email_hash)
      end

      def amount_cents
        @amount_cents ||= storefront.sold_plan(subscription.plan.code)&.dig("free_credits_cents").to_i
      end

      def credits
        BigDecimal(amount_cents) / Money::Currency.new(wallet.currency).subunit_to_unit / wallet.rate_amount
      end

      # The grant row goes in first: a mailbox already served fails here, before any credit is written.
      def create_grant
        grant = Agents::FreeCreditGrant.create!(organization: storefront.organization, storefront:, registration:, email_hash:, amount_cents:)

        # The balance increase retries on a stale wallet by running its whole body again, which in our transaction
        # would keep the first attempt's granted row: the wallet is held until the commit, so nothing makes it stale.
        wallet.lock!

        granted = WalletTransactions::CreateFromParamsService.call(
          organization: storefront.organization,
          params: {wallet_id: wallet.id, granted_credits: credits.to_s("F")}
        )
        granted.raise_if_error!

        grant.update!(wallet_transaction: granted.wallet_transactions.first)
        result.grant = grant
        result.replayed = false
      end
    end
  end
end
