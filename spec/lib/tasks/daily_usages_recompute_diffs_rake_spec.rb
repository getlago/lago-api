# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "daily_usages:recompute_diffs" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["daily_usages:recompute_diffs"] }
  let(:organization) { create(:organization, api_keys: []) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }

  let(:from_datetime) { 10.days.ago.beginning_of_day }
  let(:to_datetime) { 20.days.from_now.end_of_day }
  let(:buggy_usage_diff) { usage_payload({"model" => %w[b]}, 1100) }

  let!(:edited_day) do
    create_daily_usage(2.days.ago.to_date, usage_payload({"model" => %w[b]}, 1100), usage_diff: buggy_usage_diff)
  end

  before do
    create_daily_usage(3.days.ago.to_date, usage_payload({"model" => %w[a b]}, 1000))

    Rake.application.rake_require("tasks/daily_usages")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { |r| "#{r}\n" })
  end

  def usage_payload(values, amount_cents)
    usage = {"amount_cents" => amount_cents, "units" => amount_cents.fdiv(100).to_s, "events_count" => amount_cents / 100}
    {
      "amount_cents" => amount_cents,
      "taxes_amount_cents" => 0,
      "charges_usage" => [
        {
          "charge" => {"lago_id" => "charge-a"},
          "filters" => [{"values" => values, "presentation_breakdowns" => [], **usage}],
          "grouped_usage" => [],
          "presentation_breakdowns" => [],
          **usage
        }
      ]
    }
  end

  def create_daily_usage(usage_date, usage, usage_diff: usage)
    create(:daily_usage, organization:, customer:, subscription:, from_datetime:, to_datetime:, usage_date:, usage:, usage_diff:)
  end

  def edited_filter_amount
    edited_day.reload.usage_diff.fetch("charges_usage").sole.fetch("filters").sole["amount_cents"]
  end

  context "when organization is not found" do
    before { stub_stdin("00000000") }

    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit)
    end
  end

  context "when user confirms" do
    before { stub_stdin(organization.id, "y", "", "", "y") }

    it "recomputes the affected daily usages" do
      expect { task.invoke }.to output(/affected daily_usages : 1/).to_stdout
      expect(edited_filter_amount).to eq(100)
    end
  end

  context "when user declines the final confirmation" do
    before { stub_stdin(organization.id, "y", "", "", "n") }

    it "aborts without updating" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/affected daily_usages : 1/).to_stdout
      expect(edited_filter_amount).to eq(1100)
    end
  end

  context "when the subscription list excludes the affected subscription" do
    let(:other_subscription) { create(:subscription, customer:, organization:) }

    before { stub_stdin(organization.id, "y", other_subscription.id, "") }

    it "finishes without updating" do
      expect { task.invoke }.to output(/Nothing to do/).to_stdout
      expect(edited_filter_amount).to eq(1100)
    end
  end

  context "when the affected row is before the from date" do
    before { stub_stdin(organization.id, "y", "", Date.current.to_s) }

    it "finishes without updating" do
      expect { task.invoke }.to output(/Nothing to do/).to_stdout
      expect(edited_filter_amount).to eq(1100)
    end
  end
end
