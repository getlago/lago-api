# frozen_string_literal: true

module Agents
  class BillingDocumentService < BaseService
    Result = BaseResult[:document]

    def initialize(storefront:)
      @storefront = storefront
      super
    end

    def call
      base = storefront.agent_url

      result.document = <<~MARKDOWN
        # Billing: #{storefront.name}

        #{storefront.name} is paid from a prepaid wallet. Enroll in one of the plans below, and each call you make is charged to your wallet. Amounts are in cents of the plan's currency.

        ## Plans

        #{sold_plans.any? ? sold_plans.map { plan_section(*it) }.join("\n") : "This storefront sells no plans yet.\n"}
        ## Enroll

        1. Get a billing token. Request a challenge as described in `#{base}/AUTH.md`, with `purpose: "authenticate"` and `scope: "billing"`, sign it, and submit the proof to `#{base}/auth/token`. A billing token only works on the billing endpoints below, and your API token only works on the API.
        2. POST `#{base}/billing/enroll` with JSON `plan_code` and `Authorization: Bearer <billing token>`. It creates your account, your subscription and an empty wallet. Enrolling again in the same plan returns the same records. A registration is enrolled in one plan only.
        3. GET `#{base}/billing` with the billing token for your plan, wallet and balance.

        Top-up limits are set when you enroll. A later change by #{storefront.name} applies to new enrollments.

        ## Add credits

        #{seller_profile ? add_credits(base) : "#{storefront.name} does not accept payments from agents yet.\n"}
      MARKDOWN

      result
    end

    private

    attr_reader :storefront

    def seller_profile
      storefront.stripe_provider&.seller_profile
    end

    def add_credits(base)
      <<~MARKDOWN
        You pay with a Stripe shared payment token granted from your own Stripe account. A token pays one top-up only.

        1. GET `#{base}/billing` with the billing token. `funding` gives the seller profile, the currency and your top-up limits.
        2. Grant a shared payment token from your Stripe account with `seller_details[network_business_profile]` set to `#{seller_profile}`, `usage_limits[currency]` set to the wallet's currency and `usage_limits[max_amount]` at least the amount, in cents.
        3. POST `#{base}/billing/payments` with JSON `amount_cents` and `shared_payment_token`, and the billing token. Sending the same token again returns the same payment.
        4. GET `#{base}/billing/payments/<id>` until `status` is `settled`: the credits are in your wallet. If it is `failed`, the token was refused: grant a new token and pay again.
      MARKDOWN
    end

    def sold_plans
      @sold_plans ||= begin
        plans = storefront.plans_for_sale.includes(charges: :billable_metric).select { X402::PlanEligibility.usage_only?(it) }.index_by(&:code)
        storefront.plans.filter_map { |sold_plan| [sold_plan, plans[sold_plan["plan_code"]]] if plans[sold_plan["plan_code"]] }
      end
    end

    def plan_section(sold_plan, plan)
      <<~MARKDOWN
        ### #{plan.name} (`#{plan.code}`)

        #{[plan.description.presence, "Billed #{plan.interval}, in #{plan.amount_currency}. #{topup_limits(sold_plan)}"].compact.join("\n\n")}

        Actions:
        #{plan.charges.sort_by { [it.created_at, it.id] }.map { action_line(it) }.join("\n")}
      MARKDOWN
    end

    def action_line(charge)
      metric = charge.billable_metric
      description = metric.description.present? ? " #{metric.description}" : ""

      "- `#{metric.code}`: #{metric.name}.#{description} Charge model `#{charge.charge_model}`, properties `#{charge.properties.to_json}`."
    end

    def topup_limits(sold_plan)
      minimum, maximum = sold_plan.values_at("minimum_topup_cents", "maximum_topup_cents")

      "Top-ups: #{minimum ? "at least #{minimum}" : "no minimum"}, #{maximum ? "at most #{maximum}" : "no maximum"}."
    end
  end
end
