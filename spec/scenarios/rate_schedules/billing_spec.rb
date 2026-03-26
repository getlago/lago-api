# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Billing Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }

  let(:product) { create(:product, organization:) }
  let(:subscription_item) { create(:product_item, :subscription, organization:, product:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, amount_currency: "EUR", pay_in_advance: false) }
  let(:plan_product) { create(:plan_product, organization:, plan:, product:) }
  let(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item: subscription_item) }
  let(:rate_schedule) do
    create(
      :rate_schedule,
      organization:,
      plan_product_item:,
      product_item: subscription_item,
      charge_model: "standard",
      billing_interval_unit: "month",
      billing_interval_count: 1,
      amount_currency: "EUR",
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

  it "creates an invoice on billing day with the subscription fee" do
    subscription = nil

    travel_to(DateTime.new(2024, 2, 1)) do
      subscription = create_v2_subscription(started_at: Time.current)
    end

    # Before billing day — no invoice
    travel_to(DateTime.new(2024, 2, 15)) do
      expect { perform_rate_schedules_billing }.not_to change(Invoice, :count)
    end

    # On billing day — creates one invoice
    travel_to(DateTime.new(2024, 3, 1, 12, 0)) do
      expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
    end

    invoice = customer.invoices.sole
    expect(invoice.fees_amount_cents).to eq(4999)
    expect(invoice.fees.count).to eq(1)
    expect(invoice.currency).to eq("EUR")

    fee = invoice.fees.sole
    expect(fee.amount_cents).to eq(4999)
    expect(fee.fee_type).to eq("product_item")
    expect(fee.units).to eq(1)

    srs = SubscriptionRateSchedule.find_by(subscription:)
    expect(srs.intervals_billed).to eq(1)
    expect(srs.next_billing_date).to eq(Date.new(2024, 4, 1))

    # Same day again — no duplicate
    travel_to(DateTime.new(2024, 3, 1, 18, 0)) do
      expect { perform_rate_schedules_billing }.not_to change(Invoice, :count)
    end
  end

  it "bills on consecutive months" do
    subscription = nil

    travel_to(DateTime.new(2024, 1, 1)) do
      subscription = create_v2_subscription(started_at: Time.current)
    end

    3.times do |i|
      travel_to(DateTime.new(2024, 2 + i, 1, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end

      srs = SubscriptionRateSchedule.find_by(subscription:)
      expect(srs.intervals_billed).to eq(i + 1)
    end

    expect(customer.invoices.count).to eq(3)
    customer.invoices.each do |invoice|
      expect(invoice.fees_amount_cents).to eq(4999)
    end
  end
end
