# frozen_string_literal: true

module Quotes
  module BillingItems
    class ValidateService < BaseService
      Result = BaseResult[:billing_items]

      COUPON_TYPES = %w[fixed_amount percentage].freeze
      ID_PREFIXES = {
        "plans" => "qtp",
        "add_ons" => "qta",
        "coupons" => "qtc",
        "wallet_credits" => "qtw"
      }.freeze
      RECURRING_RULE_PREFIX = "qtrr"

      def initialize(organization:, order_type:, billing_items:)
        @organization = organization
        @order_type = order_type.to_s
        @billing_items = billing_items || {}
        super
      end

      def call
        errors = []

        errors.concat(validate_type_constraints)
        errors.concat(validate_plans) if subscription_type?
        errors.concat(validate_add_ons) if one_off_type?
        errors.concat(validate_coupons) if subscription_type?
        errors.concat(validate_wallet_credits) if subscription_type?

        return result.validation_failure!(errors: {billing_items: errors}) if errors.any?

        result.billing_items = normalized_billing_items
        result
      end

      private

      attr_reader :organization, :order_type, :billing_items

      def subscription_type?
        order_type == "subscription_creation" || order_type == "subscription_amendment"
      end

      def one_off_type?
        order_type == "one_off"
      end

      def validate_type_constraints
        errors = []

        if one_off_type? && plans_present?
          errors << "plans not allowed for one_off order type"
        end

        if one_off_type? && coupons_present?
          errors << "coupons not allowed for one_off order type"
        end

        if one_off_type? && wallet_credits_present?
          errors << "wallet_credits not allowed for one_off order type"
        end

        if subscription_type? && add_ons_present?
          errors << "add_ons not allowed for subscription order type"
        end

        errors
      end

      def validate_plans
        errors = []
        plans = billing_items.fetch("plans", [])

        plans.each_with_index do |plan, index|
          plan_id = plan["plan_id"] || plan[:plan_id]

          if plan_id.blank?
            errors << "plans[#{index}].plan_id is required"
            next
          end

          unless organization.plans.exists?(id: plan_id)
            errors << "plans[#{index}].plan_id: plan not found in organization"
          end
        end

        errors
      end

      def validate_add_ons
        errors = []
        add_ons = billing_items.fetch("add_ons", [])

        add_ons.each_with_index do |add_on, index|
          add_on_id = add_on["add_on_id"] || add_on[:add_on_id]
          amount_cents = add_on["amount_cents"] || add_on[:amount_cents]
          name = add_on["name"] || add_on[:name]

          if name.blank?
            errors << "add_ons[#{index}].name is required"
          end

          if add_on_id.present?
            unless organization.add_ons.exists?(id: add_on_id)
              errors << "add_ons[#{index}].add_on_id: add_on not found in organization"
            end
          elsif amount_cents.blank?
            errors << "add_ons[#{index}].amount_cents is required when add_on_id is not provided"
          end
        end

        errors
      end

      def validate_coupons
        errors = []
        coupons = billing_items.fetch("coupons", [])

        coupons.each_with_index do |coupon, index|
          coupon_id = coupon["coupon_id"] || coupon[:coupon_id]
          coupon_type = coupon["coupon_type"] || coupon[:coupon_type]

          if coupon_id.blank?
            errors << "coupons[#{index}].coupon_id is required"
            next
          end

          unless organization.coupons.exists?(id: coupon_id)
            errors << "coupons[#{index}].coupon_id: coupon not found in organization"
          end

          unless COUPON_TYPES.include?(coupon_type.to_s)
            errors << "coupons[#{index}].coupon_type is invalid"
          end
        end

        errors
      end

      def validate_wallet_credits
        []
        # No catalog reference needed for wallet credits
      end

      def normalized_billing_items
        result = billing_items.dup.transform_keys(&:to_s)

        if subscription_type?
          result["plans"] = normalize_items(result.fetch("plans", []), prefix: ID_PREFIXES["plans"])
          result["coupons"] = normalize_items(result.fetch("coupons", []), prefix: ID_PREFIXES["coupons"])
          result["wallet_credits"] = normalize_wallet_credits(result.fetch("wallet_credits", []))
        end

        if one_off_type?
          result["add_ons"] = normalize_items(result.fetch("add_ons", []), prefix: ID_PREFIXES["add_ons"])
        end

        result
      end

      def normalize_items(items, prefix:)
        items.map do |item|
          item = item.transform_keys(&:to_s)
          item["id"] = "#{prefix}_#{SecureRandom.uuid}" if item["id"].blank?
          item
        end
      end

      def normalize_wallet_credits(items)
        items.map do |item|
          item = item.transform_keys(&:to_s)
          item["id"] = "#{ID_PREFIXES["wallet_credits"]}_#{SecureRandom.uuid}" if item["id"].blank?
          item["recurring_transaction_rules"] = normalize_recurring_rules(item.fetch("recurring_transaction_rules", []))
          item
        end
      end

      def normalize_recurring_rules(rules)
        rules.map do |rule|
          rule = rule.transform_keys(&:to_s)
          rule["id"] = "#{RECURRING_RULE_PREFIX}_#{SecureRandom.uuid}" if rule["id"].blank?
          rule
        end
      end

      def plans_present?
        billing_items.fetch("plans", billing_items.fetch(:plans, [])).any?
      end

      def coupons_present?
        billing_items.fetch("coupons", billing_items.fetch(:coupons, [])).any?
      end

      def wallet_credits_present?
        billing_items.fetch("wallet_credits", billing_items.fetch(:wallet_credits, [])).any?
      end

      def add_ons_present?
        billing_items.fetch("add_ons", billing_items.fetch(:add_ons, [])).any?
      end
    end
  end
end
