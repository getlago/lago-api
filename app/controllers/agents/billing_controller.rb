# frozen_string_literal: true

module Agents
  class BillingController < BaseController
    before_action :authenticate_billing_token

    def enroll
      result = Agents::Billing::EnrollService.call(storefront:, registration:, plan_code: params[:plan_code])

      if result.success?
        render(json: billing_json(result.subscription, result.wallet))
      elsif too_many_requests?(result)
        render_too_many_requests
      else
        render_error_response(result)
      end
    end

    def show
      subscription = registration.subscription

      if subscription
        render(json: billing_json(subscription, registration.wallet))
      else
        render(json: {registration_id: registration.id, enrolled: false})
      end
    end

    def pay
      result = Agents::Billing::PayService.call(storefront:, registration:, params: params.permit(:amount_cents, :shared_payment_token))

      if result.success?
        render(json: payment_json(result.wallet_transaction))
      else
        render_error_response(result)
      end
    end

    def payment
      wallet_transaction = registration.wallet&.wallet_transactions&.inbound&.purchased&.find_by(id: params[:id])
      return not_found_error(resource: "payment") unless wallet_transaction

      render(json: payment_json(wallet_transaction))
    end

    def free_credits
      result = Agents::Billing::GrantFreeCreditsService.call(storefront:, registration:)

      if result.success?
        render(json: free_credits_json(result.grant))
      else
        render_error_response(result)
      end
    end

    private

    def billing_json(subscription, wallet)
      {
        registration_id: registration.id,
        enrolled: true,
        plan_code: subscription.plan.code,
        external_subscription_id: subscription.external_id,
        wallet_code: wallet&.code,
        currency: wallet&.currency,
        balance_cents: wallet&.balance_cents,
        ongoing_balance_cents: wallet&.ongoing_balance_cents,
        funding: wallet && {
          seller_profile: storefront.stripe_provider&.seller_profile,
          currency: wallet.currency,
          minimum_topup_cents: wallet.paid_top_up_min_amount_cents,
          maximum_topup_cents: wallet.paid_top_up_max_amount_cents
        }
      }
    end

    def payment_json(wallet_transaction)
      {
        id: wallet_transaction.id,
        status: wallet_transaction.status,
        amount_cents: wallet_transaction.amount_cents.to_i,
        currency: wallet_transaction.wallet.currency,
        created_at: wallet_transaction.created_at.iso8601,
        settled_at: wallet_transaction.settled_at&.iso8601,
        failed_at: wallet_transaction.failed_at&.iso8601
      }
    end

    def free_credits_json(grant)
      {status: "granted", amount_cents: grant.amount_cents, wallet_transaction_id: grant.wallet_transaction_id}
    end
  end
end
