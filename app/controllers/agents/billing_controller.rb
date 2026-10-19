# frozen_string_literal: true

module Agents
  class BillingController < BaseController
    before_action :authenticate_billing_token

    def enroll
      result = Agents::Billing::EnrollService.call(storefront:, registration:, plan_code: params[:plan_code])

      if result.success?
        render(json: billing_json(result.subscription, result.wallet))
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

    private

    attr_reader :registration

    def authenticate_billing_token
      result = Agents::Auth::VerifyTokenService.call(storefront:, token: bearer_token, scope: Agents::Auth::ChallengeService::BILLING_SCOPE)
      if result.success?
        @registration = result.registration
      else
        render_error_response(result)
      end
    end

    def billing_json(subscription, wallet)
      {
        registration_id: registration.id,
        enrolled: true,
        plan_code: subscription.plan.code,
        external_subscription_id: subscription.external_id,
        wallet_code: wallet&.code,
        currency: wallet&.currency,
        balance_cents: wallet&.balance_cents,
        ongoing_balance_cents: wallet&.ongoing_balance_cents
      }
    end
  end
end
