# frozen_string_literal: true

require_relative "errors"

module BillingMatrix
  class World
    HASH_SECTIONS = %w[organization billing_entity plan customer].freeze
    LIST_SECTIONS = %w[taxes add_ons metrics charges fixed_charges thresholds coupons wallets plans].freeze
    NESTED_CUSTOMER_KEYS = %w[
      invoice_grace_period document_locale subscription_invoice_issuing_date_anchor
      subscription_invoice_issuing_date_adjustment
    ].freeze
    KEYS = {
      "organization" => %w[premium_integrations custom_aggregation currency],
      "billing_entity" => %w[
        name email legal_name legal_number tax_identification_number address_line1 address_line2 phone zipcode
        city state country default_currency document_numbering document_number_prefix finalize_zero_amount_invoice
        net_payment_term tax_codes timezone eu_tax_management billing_configuration
      ],
      "taxes" => %w[code name description rate applied_to_organization],
      "add_ons" => %w[code name invoice_display_name description amount_cents amount_currency tax_codes],
      "metrics" => %w[
        code name description aggregation_type weighted_interval recurring field_name expression
        rounding_function rounding_precision filters
      ],
      "plan" => %w[
        code name invoice_display_name interval description amount_cents amount_currency trial_period
        pay_in_advance bill_charges_monthly bill_fixed_charges_monthly tax_codes minimum_commitment
      ],
      "plans" => %w[
        code name invoice_display_name interval description amount_cents amount_currency trial_period
        pay_in_advance bill_charges_monthly bill_fixed_charges_monthly tax_codes minimum_commitment
        charges thresholds
      ],
      "charges" => %w[
        metric code invoice_display_name charge_model pay_in_advance prorated invoiceable regroup_paid_fees
        min_amount_cents accepts_target_wallet properties filters tax_codes applied_pricing_unit
      ],
      "fixed_charges" => %w[
        add_on code invoice_display_name units apply_units_immediately charge_model pay_in_advance prorated
        properties tax_codes
      ],
      "thresholds" => %w[amount_cents recurring threshold_display_name],
      "customer" => %w[
        external_id name currency timezone country net_payment_term finalize_zero_amount_invoice tax_codes
        email legal_name legal_number tax_identification_number address_line1 address_line2 city state zipcode
        billing_entity_code
      ] + NESTED_CUSTOMER_KEYS,
      "coupons" => %w[
        code name description coupon_type amount_cents amount_currency percentage_rate frequency
        frequency_duration expiration expiration_at reusable applies_to
      ],
      "wallets" => %w[
        code name currency rate_amount priority paid_credits granted_credits expiration_at
        invoice_requires_successful_payment paid_top_up_min_amount_cents paid_top_up_max_amount_cents
        recurring_transaction_rules
      ]
    }.freeze
    REQUIRED_KEYS = {
      "taxes" => %w[code rate],
      "add_ons" => %w[code amount_cents],
      "metrics" => %w[code aggregation_type],
      "charges" => %w[metric charge_model],
      "fixed_charges" => %w[add_on charge_model units],
      "thresholds" => %w[amount_cents],
      "coupons" => %w[code coupon_type frequency],
      "wallets" => %w[rate_amount],
      "plans" => %w[code]
    }.freeze
    PREMIUM_FEATURE_OF = {"thresholds" => "progressive_billing"}.freeze
    PLAN_SECTIONS = %w[plan charges fixed_charges thresholds].freeze
    PREMIUM_KEY = "premium"

    def self.build!(ctx, setup)
      new(ctx, setup || {}).build!
    end

    def self.validate!(setup)
      raise InvalidRow, "must be a mapping, got #{setup.class}" unless setup.is_a?(Hash)

      unknown = setup.keys.map(&:to_s) - KEYS.keys - [PREMIUM_KEY]
      raise InvalidRow, "unknown key(s) #{unknown.inspect}; supported: #{PREMIUM_KEY}, #{KEYS.keys.join(", ")}" if unknown.any?

      validate_premium!(setup)
      HASH_SECTIONS.each { |section| validate_entry!(setup[section], section, section) if setup.key?(section) }
      LIST_SECTIONS.each do |section|
        next unless setup.key?(section)

        entries = setup[section]
        raise InvalidRow, "#{section}: must be a non-empty list" unless entries.is_a?(Array) && entries.any?
        entries.each_with_index { |entry, index| validate_entry!(entry, section, "#{section}[#{index + 1}]") }
      end
      validate_references!(setup)
      nil
    end

    def self.validate_premium!(setup)
      return unless setup.key?(PREMIUM_KEY)

      value = setup[PREMIUM_KEY]
      raise InvalidRow, "#{PREMIUM_KEY}: must be true or false, got #{value.inspect}" unless [true, false].include?(value)
      return if value || Array(setup.dig("organization", "premium_integrations")).empty?

      raise InvalidRow, "organization.premium_integrations: contradicts `#{PREMIUM_KEY}: false`; every premium " \
                        "integration is also gated on License.premium?, so the row would test nothing"
    end

    def self.validate_entry!(entry, section, field)
      raise InvalidRow, "#{field}: must be a mapping" unless entry.is_a?(Hash)

      unknown = entry.keys.map(&:to_s) - KEYS.fetch(section)
      raise InvalidRow, "#{field}: unknown key(s) #{unknown.inspect}; the API would drop them silently" if unknown.any?

      missing = REQUIRED_KEYS.fetch(section, []) - entry.keys.map(&:to_s)
      raise InvalidRow, "#{field}: missing #{missing.inspect}" if missing.any?
    end

    def self.validate_references!(setup)
      metric_codes = Array(setup["metrics"]).map { |metric| metric["code"] }
      validate_charge_metrics!(setup["charges"], metric_codes, "charges")

      primary_code = setup.dig("plan", "code") || "plan"
      Array(setup["plans"]).each_with_index do |plan, index|
        field = "plans[#{index + 1}]"
        if plan["code"] == primary_code
          raise InvalidRow, "#{field}.code: #{plan["code"].inspect} is the primary plan's code; extra plans need their own"
        end

        Array(plan["charges"]).each_with_index do |charge, charge_index|
          validate_entry!(charge, "charges", "#{field}.charges[#{charge_index + 1}]")
        end
        Array(plan["thresholds"]).each_with_index do |threshold, threshold_index|
          validate_entry!(threshold, "thresholds", "#{field}.thresholds[#{threshold_index + 1}]")
        end
        validate_charge_metrics!(plan["charges"], metric_codes, "#{field}.charges")
      end

      add_on_codes = Array(setup["add_ons"]).map { |add_on| add_on["code"] }
      Array(setup["fixed_charges"]).each_with_index do |fixed_charge, index|
        next if add_on_codes.include?(fixed_charge["add_on"])

        raise InvalidRow, "fixed_charges[#{index + 1}].add_on: #{fixed_charge["add_on"].inspect} is not declared in add_ons #{add_on_codes.inspect}"
      end

      Array(setup["coupons"]).each_with_index do |coupon, index|
        next unless coupon["coupon_type"].to_s == "fixed_amount" && coupon["amount_cents"].nil?

        raise InvalidRow, "coupons[#{index + 1}].amount_cents: is required for a fixed_amount coupon"
      end
    end

    def self.validate_charge_metrics!(charges, metric_codes, field)
      Array(charges).each_with_index do |charge, index|
        next if metric_codes.include?(charge["metric"])

        raise InvalidRow, "#{field}[#{index + 1}].metric: #{charge["metric"].inspect} is not declared in metrics #{metric_codes.inspect}"
      end
    end

    def self.customer_params(attributes)
      attributes = attributes.transform_keys(&:to_s)
      nested = attributes.slice(*NESTED_CUSTOMER_KEYS)
      body = attributes.except(*NESTED_CUSTOMER_KEYS).transform_keys(&:to_sym)
      body[:billing_configuration] = nested.transform_keys(&:to_sym) if nested.any?
      body
    end

    def initialize(ctx, setup)
      @ctx = ctx
      @setup = setup
    end

    def build!
      self.class.validate!(setup)
      ctx.premium = setup[PREMIUM_KEY] if setup.key?(PREMIUM_KEY)
      create_organization
      create_taxes
      update_billing_entity if setup.key?("billing_entity")
      create_add_ons
      create_metrics
      create_plan if PLAN_SECTIONS.any? { |section| setup.key?(section) }
      create_extra_plans
      create_customer
      create_coupons
      create_wallets
      nil
    end

    private

    attr_reader :ctx, :setup

    def section(name) = setup[name] || {}

    def list(name) = Array(setup[name])

    def currency
      setup.dig("customer", "currency") || setup.dig("plan", "amount_currency") || "EUR"
    end

    def create_organization
      spec = section("organization")
      attributes = {premium_integrations: premium_integrations(spec), webhook_url: nil}
      attributes[:default_currency] = spec["currency"] if spec.key?("currency")
      attributes[:custom_aggregation] = spec["custom_aggregation"] if spec.key?("custom_aggregation")

      ctx.organization = ctx.create(:organization, **attributes)
      ctx.billing_entity = ctx.organization.default_billing_entity
      return unless spec.key?("currency")

      ctx.update_billing_entity(ctx.billing_entity, {default_currency: spec["currency"]})
      ctx.organization.reload
    end

    # A setup section that needs a premium integration implies it only under a premium licence;
    # a row that turned the licence off is asking to see the feature no-op, not to be rescued.
    def premium_integrations(spec)
      return [] unless ctx.premium?

      asked = Array(spec["premium_integrations"]).map(&:to_s)
      implied = PREMIUM_FEATURE_OF.select { |section, _| setup.key?(section) }.values
      wanted = asked | implied
      unknown = wanted - Organization::PREMIUM_INTEGRATIONS
      if unknown.any?
        raise InvalidRow, "setup.organization.premium_integrations: unknown #{unknown.inspect}; " \
                          "known: #{Organization::PREMIUM_INTEGRATIONS.inspect}"
      end
      wanted
    end

    def update_billing_entity
      ctx.update_billing_entity(ctx.billing_entity, section("billing_entity").deep_symbolize_keys)
      ctx.billing_entity.reload
    end

    def create_taxes
      list("taxes").each do |tax|
        ctx.create_tax({name: tax["code"], applied_to_organization: true}.merge(tax.transform_keys(&:to_sym)))
      end
      ctx.tax = sole(ctx.organization.taxes)
    end

    def create_add_ons
      list("add_ons").each do |add_on|
        body = {name: add_on["code"], amount_currency: currency}.merge(add_on.transform_keys(&:to_sym))
        ctx.api_call { ctx.post_with_token(ctx.organization, "/api/v1/add_ons", {add_on: body}) }
      end
    end

    def create_metrics
      list("metrics").each do |metric|
        ctx.create_metric({name: metric["code"]}.merge(metric.deep_symbolize_keys))
      end
      ctx.billable_metric = sole(ctx.organization.billable_metrics)
    end

    def create_plan
      spec = section("plan")
      code = spec.fetch("code", "plan")
      body = plan_body(spec, code)
      body[:charges] = list("charges").map { |charge| charge_params(charge) }
      body[:fixed_charges] = list("fixed_charges").map { |fixed_charge| fixed_charge_params(fixed_charge) }
      body[:usage_thresholds] = list("thresholds").map { |threshold| threshold.transform_keys(&:to_sym) }

      ctx.create_plan(body)
      ctx.plan = ctx.organization.plans.find_by!(code:)
      verify_plan!
    end

    # Extra plans exist so a timeline can move the subscription onto them (an upgrade is
    # `create_subscription` with the same external_id and another plan_code). ctx.plan stays
    # the primary plan, so `update_plan` / `update_charge` keep targeting it.
    def create_extra_plans
      list("plans").each do |spec|
        code = spec.fetch("code")
        body = plan_body(spec.except("charges", "thresholds"), code)
        body[:charges] = Array(spec["charges"]).map { |charge| charge_params(charge) }
        body[:usage_thresholds] = Array(spec["thresholds"]).map { |threshold| threshold.transform_keys(&:to_sym) }

        ctx.create_plan(body)
        plan = ctx.organization.plans.find_by!(code:)
        expect_count!("plans[#{code}].charges", body[:charges].size, plan.charges.parents.count)
        expect_count!("plans[#{code}].thresholds", body[:usage_thresholds].size, plan.usage_thresholds.count)
      end
    end

    def plan_body(spec, code)
      {name: code, code:, interval: "monthly", amount_cents: 0, amount_currency: currency, pay_in_advance: false}
        .merge(spec.deep_symbolize_keys)
    end

    def charge_params(charge)
      body = charge.deep_symbolize_keys
      code = body.delete(:metric)
      body[:billable_metric_id] = ctx.organization.billable_metrics.find_by!(code:).id
      body[:properties] ||= {}
      body
    end

    # The subscription fixed-charge endpoint addresses a fixed charge by its own `code`, which the
    # API leaves nil unless given, so the add-on code doubles as the fixed charge code by default.
    def fixed_charge_params(fixed_charge)
      body = fixed_charge.deep_symbolize_keys
      code = body.delete(:add_on)
      body[:add_on_id] = ctx.organization.add_ons.find_by!(code:).id
      body[:code] ||= code
      body[:properties] ||= {}
      body
    end

    def verify_plan!
      plan = ctx.plan
      expect_count!("charges", list("charges").size, plan.charges.parents.count)
      expect_count!("fixed_charges", list("fixed_charges").size, plan.fixed_charges.parents.count)
      expect_count!("thresholds", list("thresholds").size, plan.usage_thresholds.count)
      if ctx.premium? && section("plan").key?("minimum_commitment") && plan.minimum_commitment.nil?
        raise Error, "setup.plan.minimum_commitment: the API answered 200 but the plan has no minimum commitment " \
                     "(it is premium-gated; License.premium? must be true)"
      end
    end

    def expect_count!(section, asked, created)
      return if asked == created

      raise Error, "setup.#{section}: asked for #{asked} but the plan was created with #{created}; " \
                   "the API dropped some silently (premium gate or unpermitted attribute)"
    end

    def create_customer
      body = {external_id: "cust", name: "Customer", currency: currency}
        .merge(self.class.customer_params(section("customer")))
      ctx.create_or_update_customer(body)
      ctx.customer = ctx.organization.customers.find_by!(external_id: body[:external_id])
    end

    def create_coupons
      list("coupons").each do |coupon|
        body = {name: coupon["code"], expiration: "no_expiration"}
        body[:amount_currency] = currency if coupon["coupon_type"].to_s == "fixed_amount"
        ctx.create_coupon(body.merge(coupon.deep_symbolize_keys))
        ctx.apply_coupon({external_customer_id: ctx.customer.external_id, coupon_code: coupon["code"]})
      end
      ctx.coupon = sole(ctx.organization.coupons)
    end

    def create_wallets
      list("wallets").each do |wallet|
        body = {currency: currency}.merge(wallet.deep_symbolize_keys).merge(external_customer_id: ctx.customer.external_id)
        ctx.create_wallet(body)
      end
      ctx.wallet = sole(ctx.customer.wallets)
    end

    def sole(relation)
      (relation.count == 1) ? relation.first : nil
    end
  end
end
