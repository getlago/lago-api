# frozen_string_literal: true

module CopyToProduction
  module Items
    class CouponItem < BaseItem
      ATTRIBUTES = %i[
        name code description coupon_type amount_cents amount_currency percentage_rate frequency frequency_duration
        expiration expiration_at reusable
      ].freeze

      def find_source(id)
        sandbox.coupons.includes(coupon_targets: :billable_metric).find_by(id:)
      end

      def find_existing(source)
        production.coupons.find_by(code: source.code)
      end

      def dependencies(source)
        targeted_metrics(source).map { ["billable_metric", it] }
      end

      # Self-serve organizations only use catalog plans, so a coupon limited to legacy plans is never moved. A coupon
      # limited to catalog plans waits for the catalog plan item type, which will make each targeted plan a parent.
      def refusal(source)
        "copy_to_production_unsupported_target" if source.coupon_targets.any? { it.plan_id || it.catalog_plan_id }
      end

      # The create service reads metric ids or codes depending on the caller, so both are given.
      def copy!(source, resolved)
        live_metrics = targeted_metrics(source).map { resolved.fetch(["billable_metric", it.id]) }
        applies_to = if live_metrics.any?
          {billable_metric_ids: live_metrics.map(&:id), billable_metric_codes: live_metrics.map(&:code)}
        end

        Coupons::CreateService.call!(
          **source.slice(*ATTRIBUTES).symbolize_keys,
          organization_id: production.id,
          applies_to:
        ).coupon
      end

      def unique_indexes
        {"index_coupons_on_organization_id_and_code" => :code}
      end

      private

      def targeted_metrics(source)
        source.coupon_targets.filter_map(&:billable_metric)
      end
    end
  end
end
