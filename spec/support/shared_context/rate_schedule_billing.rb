# frozen_string_literal: true

RSpec.shared_context "with rate schedule billing" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }

  let(:product) { create(:product, organization:) }
  let(:subscription_item) { create(:product_item, :subscription, organization:, product:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, amount_currency: "EUR", pay_in_advance: false) }
  let(:plan_product) { create(:plan_product, organization:, plan:, product:) }
  let(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item: subscription_item) }
  let(:billing_interval_count) { 1 }
  let(:prorated) { false }
  let(:anchor_date) { nil }
  let(:rate_schedule) do
    create(
      :rate_schedule,
      organization:,
      plan_product_item:,
      product_item: subscription_item,
      charge_model: "standard",
      billing_interval_unit:,
      billing_interval_count:,
      amount_currency: "EUR",
      prorated:,
      properties: {"amount" => "49.99"},
      position: 0
    )
  end

  before do
    plan_product
    rate_schedule
  end

  def create_v2_subscription(started_at:, external_id: "sub_test")
    subscription = create(
      :subscription,
      organization:,
      customer:,
      plan:,
      external_id:,
      started_at:,
      subscription_at: started_at,
      anchor_date:,
      status: :active,
      billing_time: :calendar
    )

    srs = SubscriptionRateSchedule.create!(
      organization:,
      subscription:,
      rate_schedule:,
      product_item: subscription_item,
      status: :active,
      started_at:
    )
    srs.update_next_billing_date!

    subscription
  end
end
