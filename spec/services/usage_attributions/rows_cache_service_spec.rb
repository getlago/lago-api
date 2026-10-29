# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributions::RowsCacheService, cache: :memory, clickhouse: {clean_before: true} do
  subject(:result) { described_class.call!(subscription:, query:) }

  around { |example| travel_to(Time.zone.parse("2026-10-20 12:00:00")) { example.run } }

  let(:subscription) { create(:subscription) }
  let(:offset) { 0 }
  let(:query) { build_query(offset:) }

  def build_query(offset:)
    Events::Stores::Clickhouse::AttributedUsageQuery.new(
      organization_id: subscription.organization_id,
      external_subscription_id: subscription.external_id,
      from_datetime: Time.zone.parse("2026-09-01"),
      to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
      group_key: "team",
      label_filters: {},
      charge_columns: [
        Events::Stores::Clickhouse::AttributedUsageQuery::ChargeColumn.new(
          charge_id: SecureRandom.uuid, code: "tokens", count: false, unit_amount_cents: BigDecimal("0.5"), lookup: nil, split_filter_ids: nil
        )
      ],
      order_by: "amount",
      search: nil,
      limit: 50,
      offset:,
      deduplicate: false,
      max_groups: 1_000,
      max_execution_time: 10
    )
  end

  def create_event(team:, value:, enriched_at:, code: "tokens", timestamp: Time.zone.parse("2026-09-10"), external_subscription_id: subscription.external_id)
    Clickhouse::EventsEnriched.create!(
      organization_id: subscription.organization_id,
      external_subscription_id:,
      code:,
      timestamp:,
      transaction_id: SecureRandom.uuid,
      properties: {},
      attribution_labels: {"team" => team},
      value: value.to_s,
      decimal_value: value,
      enriched_at:
    )
  end

  def nodes(rows)
    rows.map { [it["node"], it["amount"]] }
  end

  before do
    create_event(team: "eng", value: 1000, enriched_at: Time.zone.parse("2026-09-10"))
    allow(query).to receive(:rows).and_call_original
    allow(query).to receive(:ingested_since?).and_call_original
  end

  context "with a cached entry" do
    before do
      result
      travel(1.hour)
    end

    it "serves the entry when no event was ingested since" do
      expect(nodes(described_class.call!(subscription:, query:).rows)).to eq([["eng", BigDecimal(500)]])
      expect(query).to have_received(:rows).once
      expect(query).to have_received(:ingested_since?).with(Time.zone.parse("2026-10-20 11:55:00"))
    end

    it "reads the query again when an event of a past day was ingested since" do
      create_event(team: "data", value: 2000, enriched_at: Time.current, timestamp: Time.zone.parse("2026-09-02"))

      expect(nodes(described_class.call!(subscription:, query:).rows)).to eq([["data", BigDecimal(1000)], ["eng", BigDecimal(500)]])
      expect(query).to have_received(:rows).twice
    end

    it "ignores the events read by other queries" do
      create_event(team: "data", value: 2000, enriched_at: Time.current, code: "requests")
      create_event(team: "data", value: 2000, enriched_at: Time.current, external_subscription_id: SecureRandom.uuid)
      create_event(team: "data", value: 2000, enriched_at: Time.current, timestamp: Time.zone.parse("2026-10-01"))

      described_class.call!(subscription:, query:)

      expect(query).to have_received(:rows).once
    end

    it "reads the query again once the entry is six hours old" do
      travel(4.hours)
      described_class.call!(subscription:, query:)
      expect(query).to have_received(:rows).once

      travel(2.hours)
      described_class.call!(subscription:, query:)
      expect(query).to have_received(:rows).twice
    end

    context "when the check fails" do
      before do
        allow(query).to receive(:ingested_since?).and_raise(ActiveRecord::StatementInvalid, "Code: 159. DB::Exception: TIMEOUT_EXCEEDED")
      end

      it "reads the query again" do
        expect(nodes(described_class.call!(subscription:, query:).rows)).to eq([["eng", BigDecimal(500)]])
        expect(query).to have_received(:rows).twice
      end
    end
  end

  context "when the events of the subscription are deleted after the read" do
    before do
      result
      travel(1.minute)
      described_class.expire_for_subscription(subscription)
    end

    it "reads the query again" do
      described_class.call!(subscription:, query:)

      expect(query).to have_received(:rows).twice
    end

    it "serves the entry read after the deletion" do
      travel(1.second)
      described_class.call!(subscription:, query:)
      travel(1.minute)
      described_class.call!(subscription:, query:)

      expect(query).to have_received(:rows).twice
    end
  end

  context "when another subscription's events are deleted" do
    before do
      result
      described_class.expire_for_subscription(create(:subscription))
    end

    it "serves the entry" do
      described_class.call!(subscription:, query:)

      expect(query).to have_received(:rows).once
    end
  end

  context "when an event is ingested within the margin of the read" do
    before do
      create_event(team: "data", value: 2000, enriched_at: 4.minutes.ago)
      result
      travel(1.hour)
    end

    it "reads the query again" do
      described_class.call!(subscription:, query:)

      expect(query).to have_received(:rows).twice
    end
  end

  context "with another query" do
    let(:other_query) { build_query(offset: 1) }

    before { allow(other_query).to receive(:rows).and_call_original }

    it "keeps a separate entry" do
      result
      described_class.call!(subscription:, query: other_query)

      expect(other_query).to have_received(:rows).once
    end
  end

  context "when the query exceeds a ClickHouse limit" do
    before do
      allow(query).to receive(:rows).and_raise(ActiveRecord::StatementInvalid, "Code: 159. DB::Exception: TIMEOUT_EXCEEDED")
    end

    it "raises the failure again without reading until it expires" do
      expect { result }.to raise_error(ActiveRecord::StatementInvalid, /TIMEOUT_EXCEEDED/)
      expect { described_class.call!(subscription:, query:) }.to raise_error(ActiveRecord::StatementInvalid, /TIMEOUT_EXCEEDED/)
      expect(query).to have_received(:rows).once

      travel(11.seconds)

      expect { described_class.call!(subscription:, query:) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(query).to have_received(:rows).twice
    end
  end

  context "when the query fails otherwise" do
    before { allow(query).to receive(:rows).and_raise(ActiveRecord::StatementInvalid, "Code: 62. DB::Exception: SYNTAX_ERROR") }

    it "does not keep the failure" do
      expect { result }.to raise_error(ActiveRecord::StatementInvalid)
      expect { described_class.call!(subscription:, query:) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(query).to have_received(:rows).twice
    end
  end

  context "with a Redis cache store", cache: :redis do
    it "returns the rows as the query read them" do
      rows = result.rows

      cached_rows = described_class.call!(subscription:, query:).rows
      expect(cached_rows).to eq(rows)
      expect(cached_rows.first.transform_values(&:class)).to eq(rows.first.transform_values(&:class))
      expect(query).to have_received(:rows).once
    end
  end
end
