# frozen_string_literal: true

# NOTE: Seeds for Billing Engine V2 (rate schedules)
#
# Run multiple times to generate more data — each run creates a new
# batch of customers with unique IDs. All start dates are relative
# to today so there is always something to bill.
#
# Config:
#   CUSTOMERS_PER_PLAN  — how many customers per plan (default 3)
#
# Usage:
#   lago exec api bin/rails runner "load 'db/seeds/25_billing_engine_v2.rb'"

CUSTOMERS_PER_PLAN = 3

organization = Organization.find_by!(name: "Hooli")
billing_entity = organization.default_billing_entity
sum_bm = BillableMetric.find_by!(organization:, code: "sum_bm")
count_bm = BillableMetric.find_by!(organization:, code: "count_bm")
today = Date.current
batch = SecureRandom.hex(4) # unique per run

# Helper: create SubscriptionRateSchedules for a plan's rate schedules
create_srs = lambda do |subscription:, plan:, started_at:, status: :active, exclude_items: [], intervals_billed: 0, intervals_to_bill: nil|
  plan.plan_product_items.includes(:rate_schedules).find_each do |ppi|
    next if exclude_items.include?(ppi.product_item)

    ppi.rate_schedules.each do |rs|
      srs = SubscriptionRateSchedule.create_with(
        status:,
        started_at:,
        intervals_billed:,
        intervals_to_bill:
      ).find_or_create_by!(
        organization:,
        subscription:,
        rate_schedule: rs,
        product_item: ppi.product_item
      )
      srs.update_next_billing_date!
    end
  end
end

# ═══════════════════════════════════════════════════════════════
# PRODUCTS & PRODUCT ITEMS (idempotent)
# ═══════════════════════════════════════════════════════════════

compute_product = Product.find_or_create_by!(organization:, code: "compute") do |p|
  p.name = "Compute"
  p.description = "Compute resources"
end

compute_sub_item = ProductItem.find_or_create_by!(organization:, product: compute_product, code: "compute_base") do |pi|
  pi.item_type = :subscription
  pi.name = "Compute Base Fee"
end

compute_fixed_item = ProductItem.find_or_create_by!(organization:, product: compute_product, code: "compute_support") do |pi|
  pi.item_type = :fixed
  pi.name = "Premium Support"
end

compute_usage_item = ProductItem.find_or_create_by!(organization:, product: compute_product, code: "compute_api_calls") do |pi|
  pi.item_type = :usage
  pi.name = "API Calls"
  pi.billable_metric = sum_bm
end

storage_product = Product.find_or_create_by!(organization:, code: "storage") do |p|
  p.name = "Storage"
  p.description = "Storage resources"
end

storage_sub_item = ProductItem.find_or_create_by!(organization:, product: storage_product, code: "storage_base") do |pi|
  pi.item_type = :subscription
  pi.name = "Storage Base Fee"
end

storage_fixed_item = ProductItem.find_or_create_by!(organization:, product: storage_product, code: "storage_backup") do |pi|
  pi.item_type = :fixed
  pi.name = "Backup Storage"
end

storage_usage_item = ProductItem.find_or_create_by!(organization:, product: storage_product, code: "storage_data_transfer") do |pi|
  pi.item_type = :usage
  pi.name = "Data Transfer"
  pi.billable_metric = sum_bm
end

networking_product = Product.find_or_create_by!(organization:, code: "networking") do |p|
  p.name = "Networking"
  p.description = "Network and CDN resources"
end

networking_sub_item = ProductItem.find_or_create_by!(organization:, product: networking_product, code: "networking_base") do |pi|
  pi.item_type = :subscription
  pi.name = "Networking Base Fee"
end

networking_usage_item = ProductItem.find_or_create_by!(organization:, product: networking_product, code: "networking_bandwidth") do |pi|
  pi.item_type = :usage
  pi.name = "Bandwidth (GB)"
  pi.billable_metric = sum_bm
end

networking_fixed_item = ProductItem.find_or_create_by!(organization:, product: networking_product, code: "networking_static_ip") do |pi|
  pi.item_type = :fixed
  pi.name = "Static IP Address"
end

analytics_product = Product.find_or_create_by!(organization:, code: "analytics") do |p|
  p.name = "Analytics"
  p.description = "Data analytics and reporting"
end

analytics_sub_item = ProductItem.find_or_create_by!(organization:, product: analytics_product, code: "analytics_base") do |pi|
  pi.item_type = :subscription
  pi.name = "Analytics Base Fee"
end

analytics_usage_item = ProductItem.find_or_create_by!(organization:, product: analytics_product, code: "analytics_queries") do |pi|
  pi.item_type = :usage
  pi.name = "Query Executions"
  pi.billable_metric = count_bm
end

# ═══════════════════════════════════════════════════════════════
# PLANS & RATE SCHEDULES (idempotent)
# ═══════════════════════════════════════════════════════════════

# Helper to DRY up plan + product + items + rate schedule wiring
wire_plan = lambda do |plan:, product:, items:|
  PlanProduct.find_or_create_by!(organization:, plan:, product:)
  items.each do |item_cfg|
    ppi = PlanProductItem.find_or_create_by!(organization:, plan:, product_item: item_cfg[:item])
    RateSchedule.find_or_create_by!(organization:, plan_product_item: ppi, product_item: item_cfg[:item], position: item_cfg.fetch(:position, 0)) do |rs|
      rs.charge_model = item_cfg.fetch(:model, :standard)
      rs.billing_interval_unit = item_cfg[:interval_unit]
      rs.billing_interval_count = item_cfg.fetch(:interval_count, 1)
      rs.amount_currency = "EUR"
      rs.pay_in_advance = item_cfg.fetch(:pay_in_advance, false)
      rs.units = item_cfg[:units] if item_cfg[:units]
      rs.properties = item_cfg[:props]
    end
  end
end

# -- Compute Monthly (arrears) --
compute_plan = Plan.find_or_create_by!(organization:, code: "v2_compute_monthly") do |p|
  p.name = "Compute Monthly (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

compute_sub_ppi = nil
wire_plan.call(plan: compute_plan, product: compute_product, items: [
  {item: compute_sub_item,   interval_unit: :month, props: {"amount" => "49.99"}},
  {item: compute_fixed_item, interval_unit: :month, props: {"amount" => "19.99"}, units: 1},
  {item: compute_usage_item, interval_unit: :month, props: {"amount" => "0.10"}}
])
compute_sub_ppi = PlanProductItem.find_by!(organization:, plan: compute_plan, product_item: compute_sub_item)

# -- Storage Weekly --
storage_plan = Plan.find_or_create_by!(organization:, code: "v2_storage_weekly") do |p|
  p.name = "Storage Weekly (V2)"
  p.interval = "weekly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: storage_plan, product: storage_product, items: [
  {item: storage_fixed_item, interval_unit: :week, props: {"amount" => "9.99"}, units: 1}
])

# -- Compute Daily --
compute_daily_plan = Plan.find_or_create_by!(organization:, code: "v2_compute_daily") do |p|
  p.name = "Compute Daily (V2)"
  p.interval = "weekly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: compute_daily_plan, product: compute_product, items: [
  {item: compute_sub_item,   interval_unit: :day, props: {"amount" => "2.99"}},
  {item: compute_usage_item, interval_unit: :day, props: {"amount" => "0.05"}}
])

# -- Compute Pay-in-Advance --
compute_advance_plan = Plan.find_or_create_by!(organization:, code: "v2_compute_advance") do |p|
  p.name = "Compute Pay-in-Advance (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = true
end

wire_plan.call(plan: compute_advance_plan, product: compute_product, items: [
  {item: compute_sub_item,   interval_unit: :month, props: {"amount" => "59.99"}, pay_in_advance: true},
  {item: compute_fixed_item, interval_unit: :month, props: {"amount" => "29.99"}, pay_in_advance: true, units: 1}
])

# -- Analytics Graduated --
analytics_graduated_plan = Plan.find_or_create_by!(organization:, code: "v2_analytics_graduated") do |p|
  p.name = "Analytics Graduated (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: analytics_graduated_plan, product: analytics_product, items: [
  {item: analytics_sub_item, interval_unit: :month, props: {"amount" => "29.99"}},
  {item: analytics_usage_item, interval_unit: :month, model: :graduated, props: {
    "graduated_ranges" => [
      {"from_value" => 0, "to_value" => 100, "per_unit_amount" => "0.50", "flat_amount" => "0"},
      {"from_value" => 101, "to_value" => 1000, "per_unit_amount" => "0.30", "flat_amount" => "0"},
      {"from_value" => 1001, "to_value" => nil, "per_unit_amount" => "0.10", "flat_amount" => "0"}
    ]
  }}
])

# -- Analytics Volume --
analytics_volume_plan = Plan.find_or_create_by!(organization:, code: "v2_analytics_volume") do |p|
  p.name = "Analytics Volume (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: analytics_volume_plan, product: analytics_product, items: [
  {item: analytics_sub_item, interval_unit: :month, props: {"amount" => "19.99"}},
  {item: analytics_usage_item, interval_unit: :month, model: :volume, props: {
    "volume_ranges" => [
      {"from_value" => 0, "to_value" => 500, "per_unit_amount" => "0.40", "flat_amount" => "10"},
      {"from_value" => 501, "to_value" => 5000, "per_unit_amount" => "0.20", "flat_amount" => "0"},
      {"from_value" => 5001, "to_value" => nil, "per_unit_amount" => "0.05", "flat_amount" => "0"}
    ]
  }}
])

# -- Networking Package --
networking_package_plan = Plan.find_or_create_by!(organization:, code: "v2_networking_package") do |p|
  p.name = "Networking Package (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: networking_package_plan, product: networking_product, items: [
  {item: networking_sub_item,   interval_unit: :month, props: {"amount" => "39.99"}},
  {item: networking_usage_item, interval_unit: :month, model: :package, props: {"amount" => "5.00", "package_size" => 100, "free_units" => 50}},
  {item: networking_fixed_item, interval_unit: :month, props: {"amount" => "4.99"}, units: 2}
])

# -- Networking Percentage --
networking_pct_plan = Plan.find_or_create_by!(organization:, code: "v2_networking_percentage") do |p|
  p.name = "Networking Percentage (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: networking_pct_plan, product: networking_product, items: [
  {item: networking_sub_item, interval_unit: :month, props: {"amount" => "14.99"}},
  {item: networking_usage_item, interval_unit: :month, model: :percentage, props: {
    "rate" => "1.5", "fixed_amount" => "0.50",
    "free_units_per_events" => 10, "free_units_per_total_aggregation" => "100",
    "per_transaction_min_amount" => "0.10", "per_transaction_max_amount" => "50.00"
  }}
])

# -- Compute Quarterly --
compute_quarterly_plan = Plan.find_or_create_by!(organization:, code: "v2_compute_quarterly") do |p|
  p.name = "Compute Quarterly (V2)"
  p.interval = "quarterly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: compute_quarterly_plan, product: compute_product, items: [
  {item: compute_sub_item,   interval_unit: :month, interval_count: 3, props: {"amount" => "129.99"}},
  {item: compute_usage_item, interval_unit: :month, interval_count: 3, props: {"amount" => "0.08"}}
])

# -- Compute Yearly --
compute_yearly_plan = Plan.find_or_create_by!(organization:, code: "v2_compute_yearly") do |p|
  p.name = "Compute Yearly (V2)"
  p.interval = "yearly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

wire_plan.call(plan: compute_yearly_plan, product: compute_product, items: [
  {item: compute_sub_item,   interval_unit: :year, props: {"amount" => "499.99"}},
  {item: compute_usage_item, interval_unit: :year, props: {"amount" => "0.05"}},
  {item: compute_fixed_item, interval_unit: :year, props: {"amount" => "99.99"}, units: 1}
])

# -- Enterprise Multi-Product --
multi_plan = Plan.find_or_create_by!(organization:, code: "v2_multi_product") do |p|
  p.name = "Enterprise Multi-Product (V2)"
  p.interval = "monthly"
  p.amount_cents = 0
  p.amount_currency = "EUR"
  p.pay_in_advance = false
end

PlanProduct.find_or_create_by!(organization:, plan: multi_plan, product: compute_product)
PlanProduct.find_or_create_by!(organization:, plan: multi_plan, product: storage_product)
PlanProduct.find_or_create_by!(organization:, plan: multi_plan, product: networking_product)

[
  [compute_sub_item,      {"amount" => "99.99"}],
  [compute_usage_item,    {"amount" => "0.10"}],
  [storage_sub_item,      {"amount" => "49.99"}],
  [storage_usage_item,    {"amount" => "0.02"}],
  [networking_sub_item,   {"amount" => "79.99"}],
  [networking_usage_item, {"amount" => "0.03"}]
].each do |item, props|
  ppi = PlanProductItem.find_or_create_by!(organization:, plan: multi_plan, product_item: item)
  RateSchedule.find_or_create_by!(organization:, plan_product_item: ppi, product_item: item, position: 0) do |rs|
    rs.charge_model = :standard
    rs.billing_interval_unit = :month
    rs.billing_interval_count = 1
    rs.amount_currency = "EUR"
    rs.properties = props
  end
end

# Chaining rate schedule (position: 1 on compute_sub_item in compute_plan)
phase2_rs = RateSchedule.find_or_create_by!(
  organization:, plan_product_item: compute_sub_ppi, product_item: compute_sub_item, position: 1
) do |rs|
  rs.charge_model = :standard
  rs.billing_interval_unit = :month
  rs.billing_interval_count = 1
  rs.amount_currency = "EUR"
  rs.properties = {"amount" => "39.99"}
end

# ═══════════════════════════════════════════════════════════════
# CUSTOMERS & SUBSCRIPTIONS (new batch each run)
#
# Date brackets — each offset is chosen so that at least one
# bracket per plan always has next_billing_date = today.
# ═══════════════════════════════════════════════════════════════

# Offsets from today — subscriptions started at (today - offset)
# will have next_billing_date = today when the interval matches.
BILLING_BRACKETS = [
  {offset: 1.day,    billing_time: :calendar,    label: "daily"},
  {offset: 1.week,   billing_time: :anniversary, label: "weekly"},
  {offset: 1.month,  billing_time: :anniversary, label: "1mo ago (BILLS TODAY for monthly)"},
  {offset: 2.months, billing_time: :anniversary, label: "2mo ago"},
  {offset: 3.months, billing_time: :anniversary, label: "3mo ago (BILLS TODAY for quarterly)"},
  {offset: 6.months, billing_time: :anniversary, label: "6mo ago"},
  {offset: 1.year,   billing_time: :anniversary, label: "1yr ago (BILLS TODAY for yearly)"}
].freeze

all_plans = [
  {plan: compute_plan,             label: "compute_monthly"},
  {plan: compute_daily_plan,       label: "compute_daily"},
  {plan: compute_advance_plan,     label: "compute_advance"},
  {plan: analytics_graduated_plan, label: "analytics_graduated"},
  {plan: analytics_volume_plan,    label: "analytics_volume"},
  {plan: networking_package_plan,  label: "networking_package"},
  {plan: networking_pct_plan,      label: "networking_pct"},
  {plan: compute_quarterly_plan,   label: "compute_quarterly"},
  {plan: compute_yearly_plan,      label: "compute_yearly"},
  {plan: multi_plan,               label: "multi_product"},
  {plan: storage_plan,             label: "storage_weekly"}
]

active_count = 0

all_plans.each do |pc|
  CUSTOMERS_PER_PLAN.times do |i|
    bracket = BILLING_BRACKETS[i % BILLING_BRACKETS.length]
    start = (today - bracket[:offset]).beginning_of_day
    ext = "v2_#{batch}_#{pc[:label]}_#{i}"

    customer = Customer.create!(
      organization:, billing_entity:,
      external_id: ext,
      name: "#{pc[:label].titleize} ##{i} [#{batch}]",
      email: "#{ext}@v2billing.test",
      currency: "EUR"
    )

    sub = Subscription.create!(
      organization:, customer:, plan: pc[:plan],
      external_id: "sub_#{ext}",
      started_at: start,
      subscription_at: start,
      status: :active,
      billing_time: bracket[:billing_time]
    )

    create_srs.call(subscription: sub, plan: pc[:plan], started_at: start)
    active_count += 1
  end
end

# -- Special cases (also per-batch) --

# Chaining: customer on compute_plan, phase 1 terminated after 3mo, phase 2 active (BILLS TODAY)
chain_start = (today - 4.months).beginning_of_day
chain_ext = "v2_#{batch}_chaining"
chain_customer = Customer.create!(
  organization:, billing_entity:,
  external_id: chain_ext,
  name: "Chaining [#{batch}]",
  email: "#{chain_ext}@v2billing.test",
  currency: "EUR"
)

chain_sub = Subscription.create!(
  organization:, customer: chain_customer, plan: compute_plan,
  external_id: "sub_#{chain_ext}",
  started_at: chain_start, subscription_at: chain_start,
  status: :active, billing_time: :calendar
)

compute_sub_rs = RateSchedule.find_by!(
  organization:, plan_product_item: compute_sub_ppi, product_item: compute_sub_item, position: 0
)

# Phase 1 — terminated
SubscriptionRateSchedule.create!(
  organization:, subscription: chain_sub,
  rate_schedule: compute_sub_rs, product_item: compute_sub_item,
  status: :terminated, started_at: chain_start,
  ended_at: chain_start + 3.months, intervals_billed: 3, intervals_to_bill: 3
)

# Phase 2 — active at $39.99
srs_p2 = SubscriptionRateSchedule.create!(
  organization:, subscription: chain_sub,
  rate_schedule: phase2_rs, product_item: compute_sub_item,
  status: :active, started_at: chain_start + 3.months
)
srs_p2.update_next_billing_date!

# Other items on the plan (fixed + usage)
create_srs.call(subscription: chain_sub, plan: compute_plan, started_at: chain_start, exclude_items: [compute_sub_item])

# Terminated subscription
term_start = (today - 3.months).beginning_of_day
term_ext = "v2_#{batch}_terminated"
term_customer = Customer.create!(
  organization:, billing_entity:,
  external_id: term_ext,
  name: "Terminated [#{batch}]",
  email: "#{term_ext}@v2billing.test",
  currency: "EUR"
)

term_sub = Subscription.create!(
  organization:, customer: term_customer, plan: compute_plan,
  external_id: "sub_#{term_ext}",
  started_at: term_start, subscription_at: term_start,
  status: :terminated, terminated_at: (today - 1.month).end_of_day,
  billing_time: :calendar
)

create_srs.call(subscription: term_sub, plan: compute_plan, started_at: term_start, status: :terminated)

# Pending subscription (starts next month)
pend_ext = "v2_#{batch}_pending"
pend_start = (today + 1.month).beginning_of_month.beginning_of_day
pend_customer = Customer.create!(
  organization:, billing_entity:,
  external_id: pend_ext,
  name: "Pending [#{batch}]",
  email: "#{pend_ext}@v2billing.test",
  currency: "EUR"
)

Subscription.create!(
  organization:, customer: pend_customer, plan: compute_plan,
  external_id: "sub_#{pend_ext}",
  started_at: pend_start, subscription_at: pend_start,
  status: :pending, billing_time: :calendar
)
# No SRS for pending — will be created on activation

# Limited billing cycles (BILLS TODAY, final cycle)
# started 6mo ago, 5 of 6 billed → next_billing_date = today
ltd_start = (today - 6.months).beginning_of_day
ltd_ext = "v2_#{batch}_limited"
ltd_customer = Customer.create!(
  organization:, billing_entity:,
  external_id: ltd_ext,
  name: "Limited Cycles [#{batch}]",
  email: "#{ltd_ext}@v2billing.test",
  currency: "EUR"
)

ltd_sub = Subscription.create!(
  organization:, customer: ltd_customer, plan: compute_plan,
  external_id: "sub_#{ltd_ext}",
  started_at: ltd_start, subscription_at: ltd_start,
  status: :active, billing_time: :anniversary
)

create_srs.call(subscription: ltd_sub, plan: compute_plan, started_at: ltd_start, intervals_billed: 5, intervals_to_bill: 6)

special_count = 4

# rubocop:disable Rails/Output
puts "Billing Engine V2 seeds — batch #{batch}:"
puts "  #{active_count} active subscriptions across #{all_plans.size} plans x #{CUSTOMERS_PER_PLAN} customers"
puts "  #{special_count} special cases (chaining, terminated, pending, limited)"
puts "  Total: #{active_count + special_count} customers created"
puts "  Date brackets: #{BILLING_BRACKETS.map { |b| b[:label] }.join(", ")}"
# rubocop:enable Rails/Output