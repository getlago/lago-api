# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeDiffService do
  subject(:diff_service) { described_class.new(daily_usage:, previous_daily_usage:) }

  let(:daily_usage) { create(:daily_usage, usage:) }
  let(:previous_daily_usage) { create(:daily_usage, usage: previous_usage) }

  def charge_usage(lago_id:, presentation_breakdowns: [], grouped_usage: [])
    {
      "charge" => {"lago_id" => lago_id},
      "units" => "0.0",
      "events_count" => 0,
      "amount_cents" => 0,
      "filters" => [],
      "grouped_usage" => grouped_usage,
      "presentation_breakdowns" => presentation_breakdowns
    }
  end

  def grouped_usage(grouped_by:, presentation_breakdowns:)
    {
      "grouped_by" => grouped_by,
      "units" => "0.0",
      "events_count" => 0,
      "amount_cents" => 0,
      "filters" => [],
      "presentation_breakdowns" => presentation_breakdowns
    }
  end

  def usage_payload(charges_usage:)
    {
      "amount_cents" => 0,
      "taxes_amount_cents" => 0,
      "charges_usage" => charges_usage
    }
  end

  describe "presentation_breakdowns" do
    context "when a presentation breakdown exists in both snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.1"},
                {"presentation_by" => {"region" => "eu"}, "units" => "0.4"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      it "diffs non-grouped usage presentation_breakdowns by presentation_by" do
        result = diff_service.call

        expect(result).to be_success

        diff_charge = result.usage_diff.fetch("charges_usage").first
        expect(diff_charge.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us"}, "units" => "0.1"},
            {"presentation_by" => {"region" => "eu"}, "units" => "0.4"}
          ]
        )
      end
    end

    context "when presentation breakdowns are nested under grouped_usage" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              grouped_usage: [
                grouped_usage(
                  grouped_by: {"country" => nil},
                  presentation_breakdowns: [
                    {"presentation_by" => {"region" => "us-east-1"}, "units" => "1.0"},
                    {"presentation_by" => {"region" => "us-east-2"}, "units" => "0.1"}
                  ]
                ),
                grouped_usage(
                  grouped_by: {"country" => "us"},
                  presentation_breakdowns: [
                    {"presentation_by" => {"region" => "us-east-1"}, "units" => "0.4"}
                  ]
                )
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              grouped_usage: [
                grouped_usage(
                  grouped_by: {"country" => nil},
                  presentation_breakdowns: [
                    {"presentation_by" => {"region" => "us-east-1"}, "units" => "1.0"}
                  ]
                )
              ]
            )
          ]
        )
      end

      it "diffs grouped_usage presentation_breakdowns by presentation_by" do
        result = diff_service.call
        expect(result).to be_success

        charge_diff = result.usage_diff.fetch("charges_usage").first
        grouped_nil = charge_diff.fetch("grouped_usage").find { |gu| gu["grouped_by"] == {"country" => nil} }

        expect(grouped_nil.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us-east-1"}, "units" => "0.0"},
            {"presentation_by" => {"region" => "us-east-2"}, "units" => "0.1"}
          ]
        )

        grouped_us = charge_diff.fetch("grouped_usage").find { |gu| gu["grouped_by"] == {"country" => "us"} }
        expect(grouped_us.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us-east-1"}, "units" => "0.4"}
          ]
        )
      end
    end

    context "when a charge is deleted between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"},
                {"presentation_by" => {"region" => "eu"}, "units" => "0.2"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            ),
            charge_usage(
              lago_id: "charge-c",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "2.0"}
              ]
            )
          ]
        )
      end

      it "diffs presentation_breakdowns only for the overlapping charge" do
        diff = diff_service.call.usage_diff
        charge_a = diff.fetch("charges_usage").first

        expect(charge_a.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us"}, "units" => "0.5"},
            {"presentation_by" => {"region" => "eu"}, "units" => "0.2"}
          ]
        )
      end
    end

    context "when a new charge is added between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"}
              ]
            ),
            charge_usage(
              lago_id: "charge-b",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "eu"}, "units" => "0.5"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      it "keeps the new charge presentation_breakdowns unchanged" do
        diff = diff_service.call.usage_diff

        charge_a = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-a" }
        expect(charge_a.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "0.5"}]
        )

        charge_b = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-b" }
        expect(charge_b.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "eu"}, "units" => "0.5"}]
        )
      end
    end

    context "when all charges are replaced between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-b",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "2.0"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      it "does not diff presentation_breakdowns when there is no overlap" do
        diff = diff_service.call.usage_diff
        charge_b = diff.fetch("charges_usage").first

        expect(charge_b.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "2.0"}]
        )
      end
    end

    context "when charges are both added and deleted between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "2.0"}
              ]
            ),
            charge_usage(
              lago_id: "charge-c",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "eu"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            ),
            charge_usage(
              lago_id: "charge-b",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "3.0"}
              ]
            )
          ]
        )
      end

      it "diffs presentation_breakdowns for the common charge and keeps new ones" do
        diff = diff_service.call.usage_diff

        charge_a = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-a" }
        expect(charge_a.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "1.0"}]
        )

        charge_c = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-c" }
        expect(charge_c.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "eu"}, "units" => "1.0"}]
        )
      end
    end

    context "when previous_daily_usage is nil" do
      let(:previous_daily_usage) { nil }

      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) { nil }

      it "returns the current usage as diff (including presentation_breakdowns)" do
        expect(diff_service.call.usage_diff).to eq(usage)
      end
    end

    context "when previous_daily_usage is not provided" do
      subject(:diff_service) { described_class.new(daily_usage:) }

      let(:subscription) { create(:subscription) }
      let(:from_datetime) { Time.zone.parse("2022-07-01T00:00:00Z") }
      let(:to_datetime) { Time.zone.parse("2022-07-31T23:59:59Z") }

      let(:daily_usage) do
        build(
          :daily_usage,
          subscription:,
          from_datetime:,
          to_datetime:,
          usage_date: Date.new(2022, 7, 15),
          usage:
        )
      end

      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      before do
        create(
          :daily_usage,
          subscription:,
          from_datetime:,
          to_datetime:,
          usage_date: Date.new(2022, 7, 14),
          usage: previous_usage
        )
      end

      it "automatically finds the previous usage and diffs presentation_breakdowns" do
        diff = diff_service.call.usage_diff
        expect(diff.fetch("charges_usage").first.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "0.5"}]
        )
      end
    end
  end
end
