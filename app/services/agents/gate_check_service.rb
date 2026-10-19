# frozen_string_literal: true

module Agents
  class GateCheckService < BaseService
    Result = BaseResult[:allowed, :reason, :external_subscription_id, :wallet_code, :balance_credits, :billing_instructions]

    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      return result.validation_failure!(errors: input_errors) if input_errors.any?
      return result.not_found_failure!(resource: "agent_storefront") unless storefront

      token = Agents::Auth::VerifyTokenService.call(storefront:, token: params[:token], scope: storefront.scope)
      return refuse_token(token.error) unless token.success?

      registration = token.registration
      subscription = registration.subscription
      @wallet = registration.wallet
      return deny("enrollment_required") unless subscription && wallet

      plan_failure = check_plan(subscription.plan)
      return plan_failure if plan_failure

      return result.single_validation_failure!(error_code: "customer_not_refreshable") if wallet.customer.error_details.tax_error.exists?

      result.external_subscription_id = subscription.external_id
      result.wallet_code = wallet.code
      result.balance_credits = wallet.credits_balance - wallet.credits_ongoing_usage_balance

      if covered?
        result.allowed = true
        result
      else
        deny("insufficient_credits")
      end
    end

    private

    attr_reader :organization, :params, :wallet

    def input_errors
      @input_errors ||= {
        storefront_code: (["value_is_mandatory"] if params[:storefront_code].blank?),
        token: (["value_is_mandatory"] if params[:token].blank?),
        billable_metric_code: (["value_is_mandatory"] if params[:billable_metric_code].blank?),
        estimated_call_cost_cents: estimate_error
      }.compact
    end

    def estimate_error
      if params[:estimated_call_cost_cents].nil?
        ["value_is_mandatory"]
      elsif !estimated_call_cost_cents&.positive? || estimated_call_cost_cents > X402::GateChecks::CheckService::MAX_ESTIMATED_CALL_COST_CENTS
        ["invalid_value"]
      end
    end

    def estimated_call_cost_cents
      return @estimated_call_cost_cents if defined?(@estimated_call_cost_cents)

      @estimated_call_cost_cents = X402::UnsignedInteger.parse(params[:estimated_call_cost_cents])
    end

    def storefront
      @storefront ||= organization.agent_storefront_integrations.find_by(code: params[:storefront_code])
    end

    def check_plan(plan)
      charges = plan.charges.joins(:billable_metric).where(billable_metric: {code: params[:billable_metric_code]}).to_a

      if charges.empty?
        result.not_found_failure!(resource: "charge")
      elsif !X402::PlanEligibility.usage_only?(plan)
        result.single_validation_failure!(error_code: "plan_not_usage_only")
      elsif !organization.events_targeting_wallets_enabled? || !charges.all?(&:accepts_target_wallet)
        result.single_validation_failure!(error_code: "charge_not_targeted")
      elsif charges.any? { it.pay_in_advance? && !it.invoiceable? }
        result.single_validation_failure!(error_code: "charge_not_invoiceable")
      end
    end

    def refuse_token(error)
      if error.message == "registration_inactive"
        result.single_validation_failure!(error_code: "registration_inactive")
      else
        result.single_validation_failure!(field: :token, error_code: "invalid_token")
      end
    end

    def deny(reason)
      result.allowed = false
      result.reason = reason
      result.billing_instructions = "#{storefront.agent_url}/BILLING.md"
      result
    end

    def covered?
      reserved = reserve
      base = wallet.balance_cents - wallet.ongoing_usage_balance_cents

      if reserved.nil?
        base >= X402::GateChecks::CheckService::DEGRADED_CALL_HEADROOM * estimated_call_cost_cents
      elsif base - reserved >= estimated_call_cost_cents
        true
      else
        reservation_counter.release(estimated_call_cost_cents)
        false
      end
    end

    def reserve
      reservation_counter.reserve(estimated_call_cost_cents) if X402::ReservationCounter.enabled?(organization)
    end

    def reservation_counter
      @reservation_counter ||= X402::ReservationCounter.new(wallet)
    end
  end
end
