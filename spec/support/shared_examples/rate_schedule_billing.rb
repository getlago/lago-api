# frozen_string_literal: true

# Shared examples for rate schedule billing scenarios.
#
# Required lets:
#   subscription_time       — DateTime when the subscription is created
#   before_billing_times    — Array of DateTimes before the first billing day
#   billing_times           — Array of DateTimes on the billing day (only 1 invoice should be created)
#   after_billing_times     — Array of DateTimes after the billing day (no new invoices)
#   consecutive_billing_times — Array of DateTimes for consecutive billing cycles

RSpec.shared_examples "a rate schedule billing without duplicated invoices" do
  it "creates a single invoice on billing day" do
    travel_to(subscription_time) do
      create_v2_subscription(started_at: Time.current)
    end

    # Before billing day — no invoice
    before_billing_times.each do |time|
      travel_to(time) do
        expect { perform_rate_schedules_billing }.not_to change(Invoice, :count)
      end
    end

    # On billing day — creates exactly one invoice even if run multiple times
    expect do
      billing_times.each do |time|
        travel_to(time) do
          perform_rate_schedules_billing
        end
      end
    end.to change(Invoice, :count).by(1)

    # After billing day — no more invoices
    after_billing_times.each do |time|
      travel_to(time) do
        expect { perform_rate_schedules_billing }.not_to change(Invoice, :count)
      end
    end

    invoice = customer.invoices.sole
    expect(invoice.fees_amount_cents).to eq(4999)
    expect(invoice.fees.count).to eq(1)
    expect(invoice.currency).to eq("EUR")

    fee = invoice.fees.sole
    expect(fee.amount_cents).to eq(4999)
    expect(fee.fee_type).to eq("product_item")
    expect(fee.units).to eq(1)
  end
end

RSpec.shared_examples "a rate schedule billing on consecutive cycles" do
  it "bills on each cycle with a fee linked to the correct cycle" do
    travel_to(subscription_time) do
      create_v2_subscription(started_at: Time.current)
    end

    subscription = customer.subscriptions.sole

    consecutive_billing_times.each_with_index do |time, i|
      travel_to(time) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end

      srs = SubscriptionRateSchedule.find_by(subscription:)
      billed_cycles = srs.cycles.joins(:fees).distinct.count
      expect(billed_cycles).to eq(i + 1)
    end

    expect(customer.invoices.count).to eq(consecutive_billing_times.count)
    customer.invoices.each do |invoice|
      expect(invoice.fees_amount_cents).to eq(4999)
    end
  end
end
