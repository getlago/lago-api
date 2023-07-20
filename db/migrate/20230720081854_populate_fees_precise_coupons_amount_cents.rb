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
          .where(invoice: { version_number: 3 })
          .includes(:invoice, applied_coupon: :coupon)
          .order('credits.created_at ASC')

        credits.each do |credit|
          if credit.applied_coupon.coupon.limited_plans
            fees = credit.invoice.fees
              .joins(:subscription)
              .where(subscription: { plan_id: credit.coupon_targets.where.not(plan_id: nil).select(:plan_id) })

            fees.find_each do |fee|
              base_amount_cents = fees.sum(:amount_cents)

              fee.precise_coupons_amount_cents += (credit.amount_cents * fee.amount_cents).fdiv(base_amount_cents)
            end

          elsif credit.applied_coupon.limited_billable_metrics
            fees = credit.invoice.fees
              .joins(:charge)
              .where(charge: {
                billable_metric_id: credit.coupon_targets.not(billable_metric_id: nil).select(:billable_metric_id),
              })

            fees.find_each do |fee|
              base_amount_cents = fees.sum(:amount_cents)

              fee.precise_coupons_amount_cents += (credit.amount_cents * fee.amount_cents).fdiv(base_amount_cents)
            end
          else
            fees = credit.invoice.fees

            fees.find_each do |fee|
              base_amount_cents = Fee.where(invoice_id: fee.invoice.id)
                .sum('fees.amount_cents - fees.precise_coupons_amount_cents')

              fee.precise_coupons_amount_cents += (credit.amount_cents * fee.amount_cents).fdiv(base_amount_cents)
              fee.save!
            end
          end
        end
      end
    end
  end
end
