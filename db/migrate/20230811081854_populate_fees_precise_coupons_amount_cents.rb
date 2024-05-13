# frozen_string_literal: true

class PopulateFeesPreciseCouponsAmountCents < ActiveRecord::Migration[7.0]
  # NOTE: redifine models to prevent schema issue in the future
  class Subscription < ApplicationRecord; end

  class CouponTarget < ApplicationRecord; end

  class Charge < ApplicationRecord; end

  class Coupon < ApplicationRecord
    has_many :coupon_targets
  end

  class Fee < ApplicationRecord
    belongs_to :subscription, optional: true
    belongs_to :charge, optional: true
  end

  class AppliedCoupon < ApplicationRecord
    belongs_to :coupon
  end

  class Invoice < ApplicationRecord
    has_many :fees
  end

  class Credit < ApplicationRecord
    belongs_to :invoice
    belongs_to :applied_coupon
  end

  def change
    reversible do |dir|
      dir.up do
        credits = Credit
          .joins(:invoice)
          .joins(applied_coupon: :coupon)
          .where('credits.amount_cents > 0')
          .where(invoices: {version_number: 3})
          .order('credits.created_at ASC')

        # NOTE: prevent migration of fees already using the field
        fees_id = Fee.where.not(precise_coupons_amount_cents: 0).pluck(:id)

        credits.each do |credit|
          if credit.applied_coupon.coupon.limited_plans
            coupon = credit.applied_coupon.coupon
            fees = credit.invoice.fees
              .where.not(id: fees_id)
              .joins(:subscription)
              .where(subscriptions: {plan_id: coupon.coupon_targets.where.not(plan_id: nil).select(:plan_id)})

            fees.find_each do |fee|
              base_amount_cents = fees.sum(:amount_cents)
              next if base_amount_cents.zero?

              fee.precise_coupons_amount_cents += (credit.amount_cents * fee.amount_cents).fdiv(base_amount_cents)
              fee.save!
            end

          elsif credit.applied_coupon.coupon.limited_billable_metrics
            coupon = credit.applied_coupon.coupon
            fees = credit.invoice.fees
              .where.not(id: fees_id)
              .joins(:charge)
              .where(charge: {
                billable_metric_id: coupon.coupon_targets
                                          .where.not(billable_metric_id: nil)
                                          .select(:billable_metric_id),
              })

            fees.find_each do |fee|
              base_amount_cents = fees.sum(:amount_cents)
              next if base_amount_cents.zero?

              fee.precise_coupons_amount_cents += (credit.amount_cents * fee.amount_cents).fdiv(base_amount_cents)
              fee.save!
            end
          else
            fees = credit.invoice.fees.where.not(id: fees_id)

            fees.find_each do |fee|
              # NOTE: When applying coupons without limitations,
              #       the base of computation is the remaining amount of all fees.
              base_amount_cents = Fee.where(invoice_id: fee.invoice_id)
                .sum('fees.amount_cents - fees.precise_coupons_amount_cents')
              next if base_amount_cents.zero?

              fee.precise_coupons_amount_cents += (credit.amount_cents * fee.amount_cents).fdiv(base_amount_cents)
              fee.save!
            end
          end
        end
      end
    end
  end
end
