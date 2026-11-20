# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeContractService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }
  let(:product_filter) { nil }
  let(:rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "EUR") }
  let(:billing_scope) { "cycle" }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
  end
  let(:timestamp) { Time.zone.parse("2027-02-11 00:05:00") }
  let(:event_timestamps) { [Time.zone.parse("2027-02-05 10:00:00"), Time.zone.parse("2027-02-10 10:00:00")] }

  before do
    contract_rate_card
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
      rate_properties: {"amount" => "2"})

    event_timestamps.each { |event_timestamp| create_event(event_timestamp) }
  end

  def create_event(event_timestamp, properties: {})
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: billable_metric.code, timestamp: event_timestamp, properties:)
  end

  it "records the usage of the metered card on the previous day" do
    expect { result }.to change(DailyUsage, :count).by(1)

    daily_usage = result.daily_usages.sole.reload
    expect(daily_usage).to have_attributes(
      organization_id: organization.id,
      customer_id: customer.id,
      subscription_id: nil,
      external_subscription_id: nil,
      contract_id: contract.id,
      contract_rate_card_id: contract_rate_card.id,
      external_contract_id: contract.external_id,
      usage_date: Date.new(2027, 2, 10),
      from_datetime: Time.zone.parse("2027-02-01"),
      to_datetime: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01")),
      refreshed_at: timestamp
    )
    expect(daily_usage.usage).to eq(
      "from_datetime" => "2027-02-01T00:00:00.000Z",
      "to_datetime" => "2027-02-28T23:59:59.999Z",
      "issuing_date" => "2027-03-01",
      "currency" => "EUR",
      "amount_cents" => 400, # 2 events at 2 EUR
      "total_amount_cents" => 400,
      "taxes_amount_cents" => 0,
      "lago_invoice_id" => nil,
      "charges_usage" => [
        {
          "units" => "2.0",
          "total_aggregated_units" => "2.0",
          "events_count" => 2,
          "amount_cents" => 400,
          "amount_currency" => "EUR",
          "pricing_unit_details" => nil,
          "contract_rate_card" => {"lago_id" => contract_rate_card.id},
          "rate_card" => {"lago_id" => rate_card.id, "code" => rate_card.code, "rate_model" => "standard"},
          "product" => {"lago_id" => product.id, "code" => product.code},
          "product_filter" => nil,
          "billable_metric" => {
            "lago_id" => billable_metric.id,
            "name" => billable_metric.name,
            "code" => billable_metric.code,
            "aggregation_type" => "count_agg"
          },
          "filters" => [],
          "grouped_usage" => []
        }
      ]
    )
    expect(daily_usage.usage_diff).to eq(daily_usage.usage)
  end

  context "with a card on a product filter" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
    let(:product_filter) do
      create(:product_filter, organization:, product:, code: "eu").tap do |filter|
        create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter:, value: "eu")
      end
    end
    let(:event_timestamps) { [] }

    before do
      create_event(Time.zone.parse("2027-02-05 10:00:00"), properties: {"region" => "eu"})
      create_event(Time.zone.parse("2027-02-10 10:00:00"), properties: {"region" => "us"})
    end

    it "records the usage of the filter, with its values" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage.usage).to eq(
        "from_datetime" => "2027-02-01T00:00:00.000Z",
        "to_datetime" => "2027-02-28T23:59:59.999Z",
        "issuing_date" => "2027-03-01",
        "currency" => "EUR",
        "amount_cents" => 200, # the eu event at 2 EUR, the us one is outside the filter
        "total_amount_cents" => 200,
        "taxes_amount_cents" => 0,
        "lago_invoice_id" => nil,
        "charges_usage" => [
          {
            "units" => "1.0",
            "total_aggregated_units" => "1.0",
            "events_count" => 1,
            "amount_cents" => 200,
            "amount_currency" => "EUR",
            "pricing_unit_details" => nil,
            "contract_rate_card" => {"lago_id" => contract_rate_card.id},
            "rate_card" => {"lago_id" => rate_card.id, "code" => rate_card.code, "rate_model" => "standard"},
            "product" => {"lago_id" => product.id, "code" => product.code},
            "product_filter" => {"lago_id" => product_filter.id, "code" => "eu", "values" => {"region" => ["eu"]}},
            "billable_metric" => {
              "lago_id" => billable_metric.id,
              "name" => billable_metric.name,
              "code" => billable_metric.code,
              "aggregation_type" => "count_agg"
            },
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      )
    end
  end

  context "when a previous day of the same window was recorded" do
    let(:event_timestamps) { [Time.zone.parse("2027-02-05 10:00:00")] }

    before do
      described_class.call!(contract:, timestamp: Time.zone.parse("2027-02-06 00:05:00"))
      create_event(Time.zone.parse("2027-02-10 10:00:00"))
    end

    it "records the difference with that day" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage.usage["amount_cents"]).to eq(400)
      expect(daily_usage.usage_diff).to include("amount_cents" => 200, "total_amount_cents" => 200) # 400 - 200 on Feb 5
      expect(daily_usage.usage_diff["charges_usage"].sole).to include(
        "units" => "1.0", "events_count" => 1, "amount_cents" => 200,
        "contract_rate_card" => {"lago_id" => contract_rate_card.id}
      )
    end
  end

  context "when the day was already recorded" do
    before { described_class.call!(contract:, timestamp:) }

    it "records nothing more" do
      expect { result }.not_to change(DailyUsage, :count)
      expect(result.daily_usages).to eq([])
    end
  end

  context "when the contract was terminated during the usage date" do
    before { contract.update!(status: :terminated, terminated_at: Time.zone.parse("2027-02-10 18:00:00")) }

    it "records its last day" do
      expect { result }.to change(DailyUsage, :count).by(1)
      expect(result.daily_usages.sole.usage_date).to eq(Date.new(2027, 2, 10))
    end
  end

  context "when the contract was terminated after a previous day of its window was recorded" do
    let(:event_timestamps) { [Time.zone.parse("2027-02-05 10:00:00")] }

    before do
      described_class.call!(contract:, timestamp: Time.zone.parse("2027-02-06 00:05:00"))
      create_event(Time.zone.parse("2027-02-10 10:00:00"))
      contract.update!(status: :terminated, terminated_at: Time.zone.parse("2027-02-10 18:00:00"))
    end

    it "records the difference with that day, although the window now ends earlier" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage.to_datetime).to be < BillingSegment.inclusive_end(Time.zone.parse("2027-03-01"))
      expect(daily_usage.usage["amount_cents"]).to eq(400)
      expect(daily_usage.usage_diff["amount_cents"]).to eq(200) # 400 - 200 on Feb 5
    end
  end

  context "when the contract was ended by date on the previous day" do
    # Terminated at the local midnight that follows its last day, Feb 9.
    before { contract.update!(status: :terminated, terminated_at: Time.zone.parse("2027-02-10 00:00:00")) }

    it "records nothing for the day after its end" do
      expect { result }.not_to change(DailyUsage, :count)
    end
  end

  context "when the contract was terminated before the usage date" do
    before { contract.update!(status: :terminated, terminated_at: Time.zone.parse("2027-02-09 18:00:00")) }

    it "records nothing" do
      expect { result }.not_to change(DailyUsage, :count)
    end
  end

  context "when the card has no usage" do
    let(:event_timestamps) { [] }

    it "records nothing" do
      expect { result }.not_to change(DailyUsage, :count)
    end
  end

  context "when the card has no usage on later runs of the scheduling window", cache: :memory do
    let(:event_timestamps) { [] }

    it "computes the usage once" do
      allow(Contracts::CurrentUsageService).to receive(:call).and_call_original

      described_class.call!(contract:, timestamp:)
      described_class.call!(contract:, timestamp: timestamp + 1.hour)

      expect(Contracts::CurrentUsageService).to have_received(:call).once
    end
  end

  context "with a fixed card" do
    let(:fixed_rate_card) { create(:rate_card, organization:, product: create(:product, :fixed, organization:)) }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: fixed_rate_card,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: fixed_rate_card, effective_from: Time.zone.parse("2027-01-01"))
    end

    it "records the metered card only" do
      expect(result.daily_usages.map(&:contract_rate_card)).to eq([contract_rate_card])
    end
  end

  context "when it is the card's billing day" do
    let(:timestamp) { Time.zone.parse("2027-03-01 00:05:00") }
    let(:event_timestamps) { [Time.zone.parse("2027-02-05 10:00:00")] }

    before do
      described_class.call!(contract:, timestamp: Time.zone.parse("2027-02-06 00:05:00"))
      create_event(Time.zone.parse("2027-02-28 10:00:00"))
      create_event(Time.zone.parse("2027-03-01 00:01:00"))
    end

    it "records the last day of the window that just closed" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage).to have_attributes(
        usage_date: Date.new(2027, 2, 28),
        from_datetime: Time.zone.parse("2027-02-01"),
        to_datetime: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01"))
      )
      expect(daily_usage.usage["amount_cents"]).to eq(400) # Feb 5 and Feb 28 events, not the March one
      expect(daily_usage.usage_diff["amount_cents"]).to eq(200) # 400 - 200 on Feb 5
    end
  end

  context "when it is the day after the card's billing day" do
    let(:timestamp) { Time.zone.parse("2027-03-02 00:05:00") }
    let(:event_timestamps) { [Time.zone.parse("2027-02-28 10:00:00"), Time.zone.parse("2027-03-01 10:00:00")] }

    before do
      described_class.call!(contract:, timestamp: Time.zone.parse("2027-03-01 00:05:00"))
    end

    it "restarts the new window from its full usage" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage).to have_attributes(
        usage_date: Date.new(2027, 3, 1),
        from_datetime: Time.zone.parse("2027-03-01"),
        to_datetime: BillingSegment.inclusive_end(Time.zone.parse("2027-04-01"))
      )
      expect(daily_usage.usage["amount_cents"]).to eq(200) # the Mar 1 event only
      expect(daily_usage.usage_diff).to eq(daily_usage.usage)
    end
  end

  context "with a customer timezone ahead of UTC" do
    let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo", currency: "EUR") }
    # Feb 11, 00:05 in Tokyo.
    let(:timestamp) { Time.zone.parse("2027-02-10 15:05:00") }

    it "records the previous day of the customer" do
      expect(result.daily_usages.sole.usage_date).to eq(Date.new(2027, 2, 10))
    end
  end

  context "when a rate takes effect inside the usage date" do
    let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo", currency: "EUR") }
    # Feb 11, 00:05 in Tokyo. The new arrears rate starts at UTC midnight, 09:00 in Tokyo on Feb 10.
    let(:timestamp) { Time.zone.parse("2027-02-10 15:05:00") }
    let(:boundary) { Time.zone.parse("2027-02-10 00:00:00") }
    let(:event_timestamps) { [Time.zone.parse("2027-02-05 01:00:00")] }

    before do
      described_class.call!(contract:, timestamp: Time.zone.parse("2027-02-05 15:05:00"))
      create(:rate_card_rate, organization:, rate_card:, effective_from: boundary, rate_properties: {"amount" => "3"})
      create_event(Time.zone.parse("2027-02-09 20:00:00")) # Feb 10, 05:00 in Tokyo, before the new rate
      create_event(Time.zone.parse("2027-02-10 03:00:00")) # Feb 10, 12:00 in Tokyo, after it
    end

    it "records the cycle in one row, with the usage of both rates" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage).to have_attributes(
        usage_date: Date.new(2027, 2, 10),
        from_datetime: Time.zone.parse("2027-01-31 15:00:00"), # Feb 1 in Tokyo
        to_datetime: BillingSegment.inclusive_end(Time.zone.parse("2027-02-28 15:00:00"))
      )
      # The Feb 5 and Feb 10 05:00 events at 2 EUR, and the Feb 10 12:00 event at 3 EUR.
      expect(daily_usage.usage["amount_cents"]).to eq(700)
      expect(daily_usage.usage_diff["amount_cents"]).to eq(500) # 700 - 200 on Feb 5
    end

    context "with segment billing" do
      let(:billing_scope) { "segment" }

      it "records the segment that ended during the day and the one that started" do
        daily_usages = result.daily_usages.map(&:reload).sort_by(&:from_datetime)

        expect(daily_usages.map(&:usage_date)).to eq([Date.new(2027, 2, 10)] * 2)

        ended, started = daily_usages
        expect(ended.to_datetime).to eq(BillingSegment.inclusive_end(boundary))
        expect(ended.usage["amount_cents"]).to eq(400) # the Feb 5 and Feb 10 05:00 events at 2 EUR
        expect(ended.usage_diff["amount_cents"]).to eq(200) # 400 - 200 on Feb 5

        expect(started.from_datetime).to eq(boundary)
        expect(started.usage["amount_cents"]).to eq(300) # the Feb 10 12:00 event at 3 EUR
        expect(started.usage_diff).to eq(started.usage)
      end
    end
  end

  context "when the rate changes twice inside the usage date" do
    let(:rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "EUR", billing_timing: "advance") }
    let(:event_timestamps) { [Time.zone.parse("2027-02-10 04:00:00")] }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-10 06:00:00"), rate_properties: {"amount" => "3"})
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-10 12:00:00"), rate_properties: {"amount" => "5"})
      create_event(Time.zone.parse("2027-02-10 08:00:00"))
      create_event(Time.zone.parse("2027-02-10 14:00:00"))
    end

    it "records the cycle in one row, named by the latest rate that priced it" do
      daily_usage = result.daily_usages.sole.reload

      expect(daily_usage.from_datetime).to eq(Time.zone.parse("2027-02-01"))
      expect(daily_usage.usage["amount_cents"]).to eq(1000) # one event at 2 EUR, one at 3 EUR and one at 5 EUR
    end

    context "with segment billing" do
      let(:billing_scope) { "segment" }

      it "records each of the three segments of the day" do
        daily_usages = result.daily_usages.map(&:reload).sort_by(&:from_datetime)

        expect(daily_usages.map { |du| du.usage["amount_cents"] }).to eq([200, 300, 500])
        expect(daily_usages.drop(1).map(&:from_datetime)).to eq([Time.zone.parse("2027-02-10 06:00:00"), Time.zone.parse("2027-02-10 12:00:00")])
      end
    end
  end
end
