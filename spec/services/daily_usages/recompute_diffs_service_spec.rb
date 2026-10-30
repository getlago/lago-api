# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::RecomputeDiffsService do
  subject(:recompute_service) { described_class.new(subscription:, from_date:, dry_run:) }

  let(:subscription) { create(:subscription) }
  let(:from_date) { Date.new(2025, 3, 1) }
  let(:dry_run) { false }
  let(:from_datetime) { Time.zone.parse("2025-03-01T00:00:00Z") }
  let(:to_datetime) { Time.zone.parse("2025-03-31T23:59:59Z") }

  let(:filters_before_edit) { [filter_usage({"model" => %w[a b]}, 1000)] }
  let(:filters_after_edit) { [filter_usage({"model" => %w[b]}, 1100)] }
  let(:buggy_usage_diff) { usage_payload([filter_usage({"model" => %w[b]}, 1100)], 100) }

  let!(:first_day) { create_daily_usage(Date.new(2025, 3, 2), usage_payload(filters_before_edit, 1000)) }
  let!(:edited_day) do
    create_daily_usage(Date.new(2025, 3, 3), usage_payload(filters_after_edit, 1100), usage_diff: buggy_usage_diff)
  end

  def filter_usage(values, amount_cents)
    {
      "values" => values,
      "amount_cents" => amount_cents,
      "units" => amount_cents.fdiv(100).to_s,
      "events_count" => amount_cents / 100,
      "presentation_breakdowns" => []
    }
  end

  def usage_payload(filters, amount_cents, grouped_usage: [])
    {
      "amount_cents" => amount_cents,
      "taxes_amount_cents" => 0,
      "charges_usage" => [
        {
          "charge" => {"lago_id" => "charge-a"},
          "amount_cents" => amount_cents,
          "units" => amount_cents.fdiv(100).to_s,
          "events_count" => amount_cents / 100,
          "filters" => filters,
          "grouped_usage" => grouped_usage,
          "presentation_breakdowns" => []
        }
      ]
    }
  end

  def create_daily_usage(usage_date, usage, usage_diff: usage, period: [from_datetime, to_datetime])
    create(
      :daily_usage,
      subscription:,
      customer: subscription.customer,
      organization: subscription.organization,
      from_datetime: period.first,
      to_datetime: period.last,
      usage_date:,
      usage:,
      usage_diff:
    )
  end

  def filter_diff(daily_usage)
    daily_usage.reload.usage_diff.fetch("charges_usage").sole.fetch("filters").sole
  end

  it "recomputes the diff of the row written after the filter edit" do
    result = recompute_service.call

    expect(result.daily_usages).to eq([edited_day])
    expect(filter_diff(edited_day)).to include("amount_cents" => 100, "units" => "1.0", "events_count" => 1)
  end

  it "does not touch the other rows" do
    expect { recompute_service.call }.not_to change { first_day.reload.usage_diff }
  end

  context "with dry_run" do
    let(:dry_run) { true }

    it "returns the affected rows without updating them" do
      result = recompute_service.call

      expect(result.daily_usages).to eq([edited_day])
      expect(edited_day.reload.usage_diff).to eq(buggy_usage_diff)
    end
  end

  context "when the affected row is before from_date" do
    let(:from_date) { Date.new(2025, 3, 4) }

    it "skips it" do
      expect(recompute_service.call.daily_usages).to be_empty
      expect(edited_day.reload.usage_diff).to eq(buggy_usage_diff)
    end
  end

  context "when from_date falls between the reference row and the affected row" do
    let(:from_date) { Date.new(2025, 3, 3) }

    it "still compares the affected row with the row before from_date" do
      expect(recompute_service.call.daily_usages).to eq([edited_day])
    end
  end

  context "when filters are only added" do
    let(:filters_after_edit) { [filter_usage({"model" => %w[a b]}, 1000), filter_usage({"model" => %w[c]}, 100)] }

    it "does not flag the row" do
      expect(recompute_service.call.daily_usages).to be_empty
    end
  end

  context "when the previous row belongs to another billing period" do
    let!(:edited_day) do
      create_daily_usage(
        Date.new(2025, 4, 2),
        usage_payload(filters_after_edit, 1100),
        usage_diff: buggy_usage_diff,
        period: [Time.zone.parse("2025-04-01T00:00:00Z"), Time.zone.parse("2025-04-30T23:59:59Z")]
      )
    end

    it "does not flag the row" do
      expect(recompute_service.call.daily_usages).to be_empty
    end
  end

  context "when the filters of a grouped usage are edited" do
    let(:filters_before_edit) { [] }
    let(:filters_after_edit) { [] }

    let!(:first_day) do
      create_daily_usage(
        Date.new(2025, 3, 2),
        usage_payload([], 1000, grouped_usage: [grouped({"model" => %w[a b]}, 1000)])
      )
    end
    let!(:edited_day) do
      create_daily_usage(
        Date.new(2025, 3, 3),
        usage_payload([], 1100, grouped_usage: [grouped({"model" => %w[b]}, 1100)]),
        usage_diff: usage_payload([], 100, grouped_usage: [grouped({"model" => %w[b]}, 1100)])
      )
    end

    def grouped(values, amount_cents)
      {
        "grouped_by" => {"region" => "eu"},
        "amount_cents" => amount_cents,
        "units" => amount_cents.fdiv(100).to_s,
        "events_count" => amount_cents / 100,
        "filters" => [filter_usage(values, amount_cents)],
        "presentation_breakdowns" => []
      }
    end

    it "recomputes the grouped filter diff" do
      recompute_service.call

      grouped_filter = edited_day.reload.usage_diff.fetch("charges_usage").sole.fetch("grouped_usage").sole.fetch("filters").sole
      expect(grouped_filter).to include("amount_cents" => 100, "events_count" => 1)
    end
  end
end
