# frozen_string_literal: true

# NOTE: Seeds for Billing Engine V2 (rate schedules)
# Creates products, product items, plans with rate schedules,
# and subscriptions with subscription_rate_schedules.
#
# Test cases:
# 1. Customer with monthly subscription + monthly fixed fee
# 2. Customer with weekly fixed fee + monthly subscription fee (mixed intervals)
# 3. Customer with two subscriptions on different plans

organization = Organization.find_by!(name: "Hooli")
billing_entity = organization.default_billing_entity
sum_bm = BillableMetric.find_by!(organization:, code: "sum_bm")

# == Products & Product Items

compute_product = Product.find_or_create_by!(organization:, code: "compute") do |p|
  p.name = "Compute"
  p.description = "Compute resources"
end

storage_product = Product.find_or_create_by!(organization:, code: "storage") do |p|
  p.name = "Storage"
  p.description = "Storage resources"
end

# Subscription item (base plan fee)
compute_sub_item = ProductItem.find_or_create_by!(organization:, product: compute_product, code: "compute_base") do |pi|
  pi.item_type = :subscription
  pi.name = "Compute Base Fee"
end

# Fixed item (e.g., a fixed monthly platform fee)
compute_fixed_item = ProductItem.find_or_create_by!(organization:, product: compute_product, code: "compute_support") do |pi|
  pi.item_type = :fixed
  pi.name = "Premium Support"
end

# Usage item
compute_usage_item = ProductItem.find_or_create_by!(organization:, product: compute_product, code: "compute_api_calls") do |pi|
  pi.item_type = :usage
  pi.name = "API Calls"
  pi.billable_metric = sum_bm
end

# Storage items — fixed, billed weekly
storage_fixed_item = ProductItem.find_or_create_by!(organization:, product: storage_product, code: "storage_backup") do |pi|
  pi.item_type = :fixed
  pi.name = "Backup Storage"
end

# == V2 Plan: Compute Monthly

compute_plan = Plan.find_or_create_by!(organization:, code: "v2_compute_monthly") do |p|
  p.name = "Compute Monthly (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

# Link product to plan
PlanProduct.find_or_create_by!(organization:, plan: compute_plan, product: compute_product)

# Link product items to plan
compute_sub_ppi = PlanProductItem.find_or_create_by!(organization:, plan: compute_plan, product_item: compute_sub_item)
compute_fixed_ppi = PlanProductItem.find_or_create_by!(organization:, plan: compute_plan, product_item: compute_fixed_item)
compute_usage_ppi = PlanProductItem.find_or_create_by!(organization:, plan: compute_plan, product_item: compute_usage_item)

# Rate schedules for the compute plan
RateSchedule.find_or_create_by!(organization:, plan_product_item: compute_sub_ppi, product_item: compute_sub_item, position: 0) do |rs|
  rs.charge_model = :standard
  rs.billing_interval_unit = :month
  rs.billing_interval_count = 1
  rs.amount_currency = "EUR"
  rs.properties = {"amount" => "49.99"}
end

RateSchedule.find_or_create_by!(organization:, plan_product_item: compute_fixed_ppi, product_item: compute_fixed_item, position: 0) do |rs|
  rs.charge_model = :standard
  rs.billing_interval_unit = :month
  rs.billing_interval_count = 1
  rs.amount_currency = "EUR"
  rs.units = 1
  rs.properties = {"amount" => "19.99"}
end

RateSchedule.find_or_create_by!(organization:, plan_product_item: compute_usage_ppi, product_item: compute_usage_item, position: 0) do |rs|
  rs.charge_model = :standard
  rs.billing_interval_unit = :month
  rs.billing_interval_count = 1
  rs.amount_currency = "EUR"
  rs.properties = {"amount" => "0.10"}
end

# == V2 Plan: Storage Weekly

storage_plan = Plan.find_or_create_by!(organization:, code: "v2_storage_weekly") do |p|
  p.name = "Storage Weekly (V2)"
  p.interval = "weekly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

PlanProduct.find_or_create_by!(organization:, plan: storage_plan, product: storage_product)

storage_fixed_ppi = PlanProductItem.find_or_create_by!(organization:, plan: storage_plan, product_item: storage_fixed_item)

RateSchedule.find_or_create_by!(organization:, plan_product_item: storage_fixed_ppi, product_item: storage_fixed_item, position: 0) do |rs|
  rs.charge_model = :standard
  rs.billing_interval_unit = :week
  rs.billing_interval_count = 1
  rs.amount_currency = "EUR"
  rs.units = 1
  rs.properties = {"amount" => "9.99"}
end

# == Case 1: Customer with monthly compute plan (subscription + fixed + usage)

case1_customer = Customer.create_with(
  name: "Alice Monthly",
  email: "alice@v2billing.test",
  currency: "EUR"
).find_or_create_by!(organization:, billing_entity:, external_id: "v2_cust_alice")

case1_subscription = Subscription.create_with(
  organization:,
  started_at: 1.month.ago.beginning_of_month,
  subscription_at: 1.month.ago.beginning_of_month,
  status: :active,
  billing_time: :calendar,
  created_at: 1.month.ago.beginning_of_month
).find_or_create_by!(customer: case1_customer, external_id: "v2_sub_alice", plan: compute_plan)

compute_plan.plan_product_items.includes(:rate_schedules).find_each do |ppi|
  ppi.rate_schedules.each do |rs|
    srs = SubscriptionRateSchedule.find_or_create_by!(
      organization:,
      subscription: case1_subscription,
      rate_schedule: rs,
      product_item: ppi.product_item
    ) do |s|
      s.status = :active
      s.started_at = case1_subscription.started_at
    end
    srs.update_next_billing_date!
  end
end

# == Case 2: Customer with mixed intervals (monthly compute + weekly storage)

case2_customer = Customer.create_with(
  name: "Bob Mixed Intervals",
  email: "bob@v2billing.test",
  currency: "EUR"
).find_or_create_by!(organization:, billing_entity:, external_id: "v2_cust_bob")

case2_compute_sub = Subscription.create_with(
  organization:,
  started_at: 1.month.ago.beginning_of_month,
  subscription_at: 1.month.ago.beginning_of_month,
  status: :active,
  billing_time: :calendar,
  created_at: 1.month.ago.beginning_of_month
).find_or_create_by!(customer: case2_customer, external_id: "v2_sub_bob_compute", plan: compute_plan)

case2_storage_sub = Subscription.create_with(
  organization:,
  started_at: 2.weeks.ago.beginning_of_week,
  subscription_at: 2.weeks.ago.beginning_of_week,
  status: :active,
  billing_time: :calendar,
  created_at: 2.weeks.ago.beginning_of_week
).find_or_create_by!(customer: case2_customer, external_id: "v2_sub_bob_storage", plan: storage_plan)

compute_plan.plan_product_items.includes(:rate_schedules).find_each do |ppi|
  ppi.rate_schedules.each do |rs|
    srs = SubscriptionRateSchedule.find_or_create_by!(
      organization:,
      subscription: case2_compute_sub,
      rate_schedule: rs,
      product_item: ppi.product_item
    ) do |s|
      s.status = :active
      s.started_at = case2_compute_sub.started_at
    end
    srs.update_next_billing_date!
  end
end

storage_plan.plan_product_items.includes(:rate_schedules).find_each do |ppi|
  ppi.rate_schedules.each do |rs|
    srs = SubscriptionRateSchedule.find_or_create_by!(
      organization:,
      subscription: case2_storage_sub,
      rate_schedule: rs,
      product_item: ppi.product_item
    ) do |s|
      s.status = :active
      s.started_at = case2_storage_sub.started_at
    end
    srs.update_next_billing_date!
  end
end

# == Case 3: Customer with rate schedule chaining (price change after 3 months)

case3_customer = Customer.create_with(
  name: "Charlie Chaining",
  email: "charlie@v2billing.test",
  currency: "EUR"
).find_or_create_by!(organization:, billing_entity:, external_id: "v2_cust_charlie")

case3_subscription = Subscription.create_with(
  organization:,
  started_at: 3.months.ago.beginning_of_month,
  subscription_at: 3.months.ago.beginning_of_month,
  status: :active,
  billing_time: :calendar,
  created_at: 3.months.ago.beginning_of_month
).find_or_create_by!(customer: case3_customer, external_id: "v2_sub_charlie", plan: compute_plan)

# For Charlie, create a chained rate schedule on the subscription item:
# Phase 1: $49.99/mo for 3 months (should be terminated by now)
# Phase 2: $39.99/mo indefinitely (currently active)
compute_sub_rs = RateSchedule.find_by!(
  organization:,
  plan_product_item: compute_sub_ppi,
  product_item: compute_sub_item,
  position: 0
)

# Phase 1 — terminated (3 months billed)
SubscriptionRateSchedule.find_or_create_by!(
  organization:,
  subscription: case3_subscription,
  rate_schedule: compute_sub_rs,
  product_item: compute_sub_item
) do |s|
  s.status = :terminated
  s.started_at = case3_subscription.started_at
  s.ended_at = case3_subscription.started_at + 3.months
  s.intervals_billed = 3
  s.intervals_to_bill = 3
end

# Phase 2 — create a second rate schedule with different pricing
phase2_rs = RateSchedule.find_or_create_by!(
  organization:,
  plan_product_item: compute_sub_ppi,
  product_item: compute_sub_item,
  position: 1
) do |rs|
  rs.charge_model = :standard
  rs.billing_interval_unit = :month
  rs.billing_interval_count = 1
  rs.amount_currency = "EUR"
  rs.properties = {"amount" => "39.99"}
end

srs_phase2 = SubscriptionRateSchedule.find_or_create_by!(
  organization:,
  subscription: case3_subscription,
  rate_schedule: phase2_rs,
  product_item: compute_sub_item
) do |s|
  s.status = :active
  s.started_at = case3_subscription.started_at + 3.months
end
srs_phase2.update_next_billing_date!

# Also add the fixed and usage SRS for Charlie
compute_plan.plan_product_items.includes(:rate_schedules).where.not(product_item: compute_sub_item).find_each do |ppi|
  ppi.rate_schedules.each do |rs|
    srs = SubscriptionRateSchedule.find_or_create_by!(
      organization:,
      subscription: case3_subscription,
      rate_schedule: rs,
      product_item: ppi.product_item
    ) do |s|
      s.status = :active
      s.started_at = case3_subscription.started_at
    end
    srs.update_next_billing_date!
  end
end

puts "✅ Billing Engine V2 seeds created:" # rubocop:disable Rails/Output
puts "  Case 1 (Alice): Monthly compute — subscription + fixed + usage" # rubocop:disable Rails/Output
puts "  Case 2 (Bob): Mixed intervals — monthly compute + weekly storage" # rubocop:disable Rails/Output
puts "  Case 3 (Charlie): Rate schedule chaining — $49.99 x3mo → $39.99 ongoing" # rubocop:disable Rails/Output
