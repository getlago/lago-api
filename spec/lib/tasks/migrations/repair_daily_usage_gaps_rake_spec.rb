# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "migrations:repair_daily_usage_gaps" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:repair_daily_usage_gaps"] }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:, timezone: "Asia/Tokyo") }
  let(:subscription) { create_subscription(customer) }

  # 2024-10-17 21:00 in Tokyo: the last day to repair is the 16th
  let(:now) { Time.zone.parse("2024-10-17 12:00:00") }
  let(:from_date) { "2024-10-14" }

  before do
    Rake.application.rake_require("tasks/migrations/repair_daily_usage_gaps")
    Rake::Task.define_task(:environment)
    task.reenable

    create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})

    # One event at noon in Tokyo on the 14th, the 15th and the 16th, and the rows the hourly job
    # wrote: the 15th was skipped, so the row of the 16th holds the usage of both days.
    [14, 15, 16].each { create_event(subscription, Time.zone.parse("2024-10-#{it} 03:00:00")) }
    travel_to(now) do
      [14, 16].each do
        date = Date.new(2024, 10, it)
        DailyUsages::FillHistoryService.call!(subscription:, from_date: date, to_date: date)
      end
    end
    [14, 16].each { row(it).update!(usage_diff: DailyUsages::ComputeDiffService.call!(daily_usage: row(it)).usage_diff) }
  end

  def create_subscription(customer)
    started_at = Time.zone.parse("2024-10-01 00:00:00")
    create(:subscription, :calendar, organization:, customer:, plan:, started_at:, subscription_at: started_at)
  end

  def create_event(subscription, timestamp)
    create(
      :event,
      organization:,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      timestamp:,
      created_at: timestamp
    )
  end

  def row(day)
    subscription.daily_usages.find_by(usage_date: Date.new(2024, 10, day))
  end

  def diff_amounts
    subscription.daily_usages.order(:usage_date).to_h { [it.usage_date.day, it.usage_diff["amount_cents"]] }
  end

  it "starts from the usage of both days in the row after the gap" do
    # 1 event * 10.00 on the 14th, then the events of the 15th and the 16th: 2 * 10.00
    expect(diff_amounts).to eq({14 => 1000, 16 => 2000})
  end

  context "without DRY_RUN" do
    it "lists the days without a daily usage and writes nothing" do
      travel_to(now) do
        expect { task.invoke(organization.id, from_date) }
          .to output(
            a_string_including(
              "[DRY RUN]",
              "subscription=#{subscription.id} timezone=Asia/Tokyo status=days_without_row days=2024-10-15 recomputed=",
              "Totals by status: days_without_row=1"
            )
          ).to_stdout
          .and not_change(DailyUsage, :count)
      end

      expect(diff_amounts).to eq({14 => 1000, 16 => 2000})
    end
  end

  context "when DRY_RUN is false" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "fills the skipped day and splits the diff of the following row" do
      travel_to(now) do
        expect { task.invoke(organization.id, from_date) }
          .to output(
            a_string_including(
              "[LIVE]",
              "subscription=#{subscription.id} timezone=Asia/Tokyo status=filled days=2024-10-15 " \
                "recomputed=2024-10-15,2024-10-16",
              "Totals by status: filled=1"
            )
          ).to_stdout
      end

      # One event * 10.00 on each day
      expect(diff_amounts).to eq({14 => 1000, 15 => 1000, 16 => 1000})
      # 2 events * 10.00 received by the end of the 15th
      expect(row(15).usage["amount_cents"]).to eq(2000)
    end

    it "changes nothing when run again" do
      travel_to(now) do
        expect { task.invoke(organization.id, from_date) }.to output.to_stdout
        task.reenable

        expect { task.invoke(organization.id, from_date) }
          .to output(a_string_including("Subscriptions with days without a daily usage: 0.")).to_stdout
          .and not_change(DailyUsage, :count)
      end

      expect(diff_amounts).to eq({14 => 1000, 15 => 1000, 16 => 1000})
    end

    context "with a customer behind UTC" do
      let(:other_customer) { create(:customer, organization:, billing_entity:, timezone: "America/Los_Angeles") }
      let(:other_subscription) { create_subscription(other_customer) }

      before { create_event(other_subscription, Time.zone.parse("2024-10-15 20:00:00")) }

      it "leaves its subscription alone" do
        travel_to(now) do
          expect { task.invoke(organization.id, from_date) }
            .to output(a_string_including("Subscriptions with days without a daily usage: 1.")).to_stdout
        end

        expect(other_subscription.daily_usages).to be_empty
      end
    end
  end

  context "without an organization" do
    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    end
  end
end
