# frozen_string_literal: true

module CopyToProduction
  module Items
    class CouponItem < BaseItem
      ATTRIBUTES = %i[
        name code description coupon_type amount_cents amount_currency percentage_rate frequency frequency_duration
        expiration reusable
      ].freeze

      def dependencies(source)
        targeted_metrics(source).map { ["billable_metric", it] }
      end

      # Only metric targets are copied; the copy would activate a terminated coupon, or apply one whose metrics are deleted
      # to every metric. An expired one, which the copy refuses too, gets the copy's own code before the copy.
      def refusal(source)
        if source.coupon_targets.any? { it.plan_id || it.catalog_plan_id }
          "copy_to_production_unsupported_target"
        elsif source.terminated? || expired?(source)
          "copy_to_production_item_inactive"
        elsif source.limited_billable_metrics? && targeted_metrics(source).empty?
          "copy_to_production_target_deleted"
        end
      end

      # The create service reads metric ids or codes depending on the caller, so both are given.
      def copy!(source, resolved)
        live_metrics = targeted_metrics(source).map { resolved.fetch(["billable_metric", it.id]) }
        applies_to = if live_metrics.any?
          {billable_metric_ids: live_metrics.map(&:id), billable_metric_codes: live_metrics.map(&:code)}
        end

        Coupons::CreateService.call!(
          **source.slice(*ATTRIBUTES).symbolize_keys,
          # Only a time limited coupon expires: the date another one keeps from an earlier setting is never read.
          expiration_at: (source.expiration_at if source.time_limit?),
          organization_id: production.id,
          applies_to:
        ).coupon
      end

      private

      def expired?(source)
        source.time_limit? && !Validators::ExpirationDateValidator.valid?(source.expiration_at)
      end

      def targeted_metrics(source)
        source.coupon_targets.filter_map(&:billable_metric).sort_by(&:code)
      end
    end
  end
end
