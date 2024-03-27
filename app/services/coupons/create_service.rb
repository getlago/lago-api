# frozen_string_literal: true

module Coupons
  class CreateService < BaseService
    def create(args)
      return result unless valid?(args)

      @limitations = args[:applies_to]&.to_h&.deep_symbolize_keys || {}
      @organization_id = args[:organization_id]

      reusable = args.key?(:reusable) ? args[:reusable] : true

      coupon = Coupon.new(
        organization_id:,
        name: args[:name],
        code: args[:code],
        description: args[:description],
        coupon_type: args[:coupon_type],
        amount_cents: args[:amount_cents],
        amount_currency: args[:amount_currency],
        percentage_rate: args[:percentage_rate],
        frequency: args[:frequency],
        frequency_duration: args[:frequency_duration],
        expiration: args[:expiration]&.to_sym,
        expiration_at: args[:expiration_at],
        limited_plans: plan_identifiers.present?,
        limited_billable_metrics: billable_metric_identifiers.present?,
        reusable:
      )

      if plan_identifiers.present? && plans.count != plan_identifiers.count
        return result.not_found_failure!(resource: "plans")
      end

      if billable_metric_identifiers.present? && billable_metrics.count != billable_metric_identifiers.count
        return result.not_found_failure!(resource: "billable_metrics")
      end

      if billable_metrics.present? && plans.present?
        return result.not_allowed_failure!(code: "only_one_limitation_type_per_coupon_allowed")
      end

      ActiveRecord::Base.transaction do
        coupon.save!

        plans.each { |plan| CouponTarget.create!(coupon:, plan:) } if plan_identifiers.present?

        if billable_metric_identifiers.present?
          billable_metrics.each { |billable_metric| CouponTarget.create!(coupon:, billable_metric:) }
        end
      end

      result.coupon = coupon
      track_coupon_created(result.coupon)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :limitations, :organization_id

    def track_coupon_created(coupon)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: "coupon_created",
        properties: {
          coupon_code: coupon.code,
          coupon_name: coupon.name,
          organization_id:
        }
      )
    end

    def plan_identifiers
      key = api_context? ? :plan_codes : :plan_ids
      limitations[key]&.compact&.uniq
    end

    def plans
      return @plans if defined? @plans
      return [] if plan_identifiers.blank?

      finder = api_context? ? :code : :id
      @plans = Plan.where(finder => plan_identifiers, :organization_id => organization_id)
    end

    def billable_metric_identifiers
      key = api_context? ? :billable_metric_codes : :billable_metric_ids
      limitations[key]&.compact&.uniq
    end

    def billable_metrics
      return @billable_metrics if defined? @billable_metrics
      return [] if billable_metric_identifiers.blank?

      finder = api_context? ? :code : :id
      @billable_metrics = BillableMetric.where(finder => billable_metric_identifiers, :organization_id => organization_id)
    end

    def valid?(args)
      Coupons::ValidateService.new(result, **args).valid?
    end
  end
end
