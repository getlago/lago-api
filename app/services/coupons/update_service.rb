# frozen_string_literal: true

module Coupons
  class UpdateService < BaseService
    def update(args)
      @coupon = result.user.coupons.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'coupon') unless coupon

      coupon.name = args[:name]
      coupon.expiration = args[:expiration]&.to_sym
      coupon.expiration_at = args[:expiration_at]

      @limitations = args[:applies_to]&.to_h&.deep_symbolize_keys || {}

      unless coupon.applied_coupons.exists?
        if !plan_identifiers.nil? && plans.count != plan_identifiers.count
          return result.not_found_failure!(resource: 'plans')
        end

        coupon.code = args[:code]
        coupon.coupon_type = args[:coupon_type]
        coupon.amount_cents = args[:amount_cents]
        coupon.amount_currency = args[:amount_currency]
        coupon.percentage_rate = args[:percentage_rate]
        coupon.frequency = args[:frequency]
        coupon.frequency_duration = args[:frequency_duration]
        coupon.reusable = args[:reusable]
        coupon.limited_plans = plan_identifiers.present? unless plan_identifiers.nil?
      end

      ActiveRecord::Base.transaction do
        coupon.save!

        process_plans unless plan_identifiers.nil? || coupon.applied_coupons.exists?
      end

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(organization:, code:, params:)
      @coupon = organization.coupons.find_by(code:)
      return result.not_found_failure!(resource: 'coupon') unless coupon

      return result unless valid?(params)

      coupon.name = params[:name] if params.key?(:name)
      coupon.expiration = params[:expiration] if params.key?(:expiration)
      coupon.expiration_at = params[:expiration_at] if params.key?(:expiration_at)

      @limitations = params[:applies_to]&.to_h&.deep_symbolize_keys || {}

      unless coupon.applied_coupons.exists?
        if !plan_identifiers.nil? && plans.count != plan_identifiers.count
          return result.not_found_failure!(resource: 'plans')
        end

        coupon.code = params[:code] if params.key?(:code)
        coupon.coupon_type = params[:coupon_type] if params.key?(:coupon_type)
        coupon.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
        coupon.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
        coupon.percentage_rate = params[:percentage_rate] if params.key?(:percentage_rate)
        coupon.frequency = params[:frequency] if params.key?(:frequency)
        coupon.frequency_duration = params[:frequency_duration] if params.key?(:frequency_duration)
        coupon.reusable = params[:reusable] if params.key?(:reusable)
        coupon.limited_plans = plan_identifiers.present? unless plan_identifiers.nil?
      end

      ActiveRecord::Base.transaction do
        coupon.save!

        process_plans unless plan_identifiers.nil? || coupon.applied_coupons.exists?
      end

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :coupon, :limitations

    def plan_identifiers
      key = api_context? ? :plan_codes : :plan_ids
      limitations[key]&.compact&.uniq
    end

    def plans
      return @plans if defined? @plans
      return [] if plan_identifiers.blank?

      finder = api_context? ? :code : :id
      @plans = Plan.where(finder => plan_identifiers, organization_id: coupon.organization_id)
    end

    def process_plans
      existing_coupon_plan_ids = coupon.coupon_plans.pluck(:plan_id)

      plans.each do |plan|
        next if existing_coupon_plan_ids.include?(plan.id)

        CouponPlan.create!(coupon:, plan:)
      end

      sanitize_coupon_plans
    end

    def sanitize_coupon_plans
      not_needed_coupon_plan_ids = coupon.coupon_plans.pluck(:plan_id) - plans.pluck(:id)

      not_needed_coupon_plan_ids.each do |coupon_plan_id|
        CouponPlan.find_by(coupon:, plan_id: coupon_plan_id).destroy!
      end
    end

    def valid?(args)
      Coupons::ValidateService.new(result, **args).valid?
    end
  end
end
