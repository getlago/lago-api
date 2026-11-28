# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "migrations:repair_daily_usage_gaps" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:repair_daily_usage_gaps"] }

  let(:organization) { create(:organization, premium_integrations: %w[revenue_analytics]) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:, timezone: "Asia/Tokyo") }
  let(:subscription) { create_subscription(customer) }

  # 2024-10-19 21:00 in Tokyo: the last day to repair is the 18th
  let(:now) { Time.zone.parse("2024-10-19 12:00:00") }
  let(:from_date) { "2024-10-12" }

  before do
    Rake.application.rake_require("tasks/migrations/repair_daily_usage_gaps")
    Rake::Task.define_task(:environment)
    task.reenable

    create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})
  end

  # FillHistoryService freezes the time of each day it computes with Timecop, which travel_to would override
  def at_now(&) = Timecop.freeze(now, &)

  def run_task(*args)
    task.reenable
    at_now { task.invoke(*args) }
  end

  def create_subscription(customer, *traits, **attributes)
    started_at = Time.zone.parse("2024-08-01 00:00:00")
    create(:subscription, :calendar, *traits, organization:, customer:, plan:, started_at:, subscription_at: started_at, **attributes)
  end

  def create_event(subscription, timestamp, properties: {})
    create(
      :event,
      organization:,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      timestamp:,
      created_at: timestamp,
      properties:
    )
  end

  # Writes the rows the hourly job left, with their diffs against each other
  def create_rows(subscription, dates)
    at_now do
      dates.each { DailyUsages::FillHistoryService.call!(subscription:, from_date: it, to_date: it) }
    end
    subscription.daily_usages.order(:usage_date).each do |row|
      row.update!(usage_diff: DailyUsages::ComputeDiffService.call!(daily_usage: row).usage_diff)
    end
  end

  def diff_amounts(subscription)
    subscription.daily_usages.order(:usage_date).to_h { [it.usage_date.day, it.usage_diff["amount_cents"]] }
  end

  context "with a subscription whose every other day was skipped" do
    # One event at noon in Tokyo from the 14th to the 18th. The hourly job skipped the 15th and the
    # 17th, so the rows of the 16th and the 18th hold the usage of two days: 2 events * 10.00.
    before do
      (14..18).each { create_event(subscription, Time.zone.parse("2024-10-#{it} 03:00:00")) }
      create_rows(subscription, [14, 16, 18].map { Date.new(2024, 10, it) })
    end

    context "without DRY_RUN" do
      it "lists what the live run would write and writes nothing" do
        expect(diff_amounts(subscription)).to eq({14 => 1000, 16 => 2000, 18 => 2000})

        # The 12th and the 13th have no row either, but no usage to fill
        expect { run_task(organization.id, from_date) }
          .to output(
            a_string_including(
              "[DRY RUN]",
              "subscription=#{subscription.id} timezone=Asia/Tokyo status=would_fill days=2024-10-15,2024-10-17 " \
                "recomputed=2024-10-15,2024-10-16,2024-10-17,2024-10-18",
              "Subscriptions to repair: 1."
            )
          ).to_stdout
          .and not_change(DailyUsage, :count)

        expect(diff_amounts(subscription)).to eq({14 => 1000, 16 => 2000, 18 => 2000})
      end
    end

    context "when DRY_RUN is false" do
      around do |example|
        ENV["DRY_RUN"] = "false"
        example.run
      ensure
        ENV["DRY_RUN"] = nil
      end

      it "fills the skipped days and splits the diffs of the following rows" do
        expect { run_task(organization.id, from_date) }
          .to output(
            a_string_including(
              "[LIVE]",
              "subscription=#{subscription.id} timezone=Asia/Tokyo status=filled days=2024-10-15,2024-10-17 " \
                "recomputed=2024-10-15,2024-10-16,2024-10-17,2024-10-18",
              "Subscriptions repaired: 1."
            )
          ).to_stdout

        # One event * 10.00 on each day
        expect(diff_amounts(subscription)).to eq({14 => 1000, 15 => 1000, 16 => 1000, 17 => 1000, 18 => 1000})
        # 2 events * 10.00 received by the end of the 15th
        expect(subscription.daily_usages.find_by(usage_date: Date.new(2024, 10, 15)).usage["amount_cents"]).to eq(2000)
      end

      it "changes nothing when run again" do
        expect { run_task(organization.id, from_date) }.to output.to_stdout

        expect { run_task(organization.id, from_date) }
          .to output(a_string_including("Subscriptions repaired: 0.")).to_stdout
          .and not_change(DailyUsage, :count)

        expect(diff_amounts(subscription)).to eq({14 => 1000, 15 => 1000, 16 => 1000, 17 => 1000, 18 => 1000})
      end

      context "when the customer's yesterday is still the hourly job's" do
        # 2024-10-20 01:00 in Tokyo: the hourly job computes the 19th in this window
        let(:now) { Time.zone.parse("2024-10-19 16:00:00") }

        before { create_event(subscription, Time.zone.parse("2024-10-19 03:00:00")) }

        it "leaves that day to the job" do
          expect { run_task(organization.id, from_date) }
            .to output(
              a_string_including("days=2024-10-15,2024-10-17 recomputed=2024-10-15,2024-10-16,2024-10-17,2024-10-18\n")
            ).to_stdout

          expect(subscription.daily_usages.find_by(usage_date: Date.new(2024, 10, 19))).to be_nil
        end
      end

      context "when the run stops on a subscription" do
        before do
          calls = 0
          allow(Invoices::CustomerUsageService).to receive(:call).and_wrap_original do |original, **kwargs|
            calls += 1
            # The 17th, after the 15th was written
            raise "usage unavailable" if calls == 2

            original.call(**kwargs)
          end
        end

        it "rolls the subscription back and repairs it on the next run" do
          expect { run_task(organization.id, from_date) }
            .to raise_error(SystemExit)
            .and output(
              a_string_including(
                "Stopped [LIVE] after 0 subscription(s). Failed on subscription #{subscription.id}: " \
                  "RuntimeError: usage unavailable."
              )
            ).to_stderr
            .and output.to_stdout

          expect(diff_amounts(subscription)).to eq({14 => 1000, 16 => 2000, 18 => 2000})

          expect { run_task(organization.id, from_date) }.to output.to_stdout
          expect(diff_amounts(subscription)).to eq({14 => 1000, 15 => 1000, 16 => 1000, 17 => 1000, 18 => 1000})
        end
      end

      context "with subscriptions it does not repair" do
        let(:other_customer) { create(:customer, organization:, billing_entity:, timezone: "America/Los_Angeles") }
        let(:behind_utc_subscription) { create_subscription(other_customer) }
        let(:skipped_subscription) { create_subscription(customer, skip_daily_usage: true) }
        let(:terminated_subscription) { create_subscription(customer, :terminated, terminated_at: now - 1.hour) }

        before do
          [behind_utc_subscription, skipped_subscription, terminated_subscription].each do
            create_event(it, Time.zone.parse("2024-10-15 03:00:00"))
          end
        end

        it "leaves them alone" do
          expect { run_task(organization.id, from_date) }
            .to output(a_string_including("Subscriptions repaired: 1.")).to_stdout

          expect(DailyUsage.where(subscription: [behind_utc_subscription, skipped_subscription, terminated_subscription]))
            .to be_empty
        end
      end
    end
  end

  context "with a recurring subscription that lost the carry-over rows of its new periods" do
    # 3 units on 2024-08-20, carried over into September and October. Only the row of the 20th exists.
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:from_date) { "2024-08-25" }

    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    before do
      create_event(subscription, Time.zone.parse("2024-08-20 03:00:00"), properties: {item_id: 3})
      create_rows(subscription, [Date.new(2024, 8, 20)])
    end

    it "fills the first day of each period with the usage of its own period" do
      expect { run_task(organization.id, from_date) }
        .to output(a_string_including("status=filled days=2024-09-01,2024-10-01 recomputed=2024-09-01,2024-10-01")).to_stdout

      rows = subscription.daily_usages.order(:usage_date).map do |row|
        [row.usage_date, row.from_datetime.in_time_zone("Asia/Tokyo").to_date, row.usage_diff["amount_cents"]]
      end
      # 3 units * 10.00, the whole usage of each period on its first row
      expect(rows).to eq([
        [Date.new(2024, 8, 20), Date.new(2024, 8, 1), 3000],
        [Date.new(2024, 9, 1), Date.new(2024, 9, 1), 3000],
        [Date.new(2024, 10, 1), Date.new(2024, 10, 1), 3000]
      ])
    end
  end

  context "with a customer whose offset reached 3 hours at the end of the range" do
    # Europe/Kyiv moves to UTC+3 on 2027-03-28, between two dates 30 days apart from the 10th.
    # 2027-04-02 15:00 in Kyiv: the last day to repair is the 1st.
    let(:customer) { create(:customer, organization:, billing_entity:, timezone: "Europe/Kyiv") }
    let(:now) { Time.zone.parse("2027-04-02 12:00:00") }

    before do
      (29..31).each { create_event(subscription, Time.zone.parse("2027-03-#{it} 09:00:00")) }
      create_rows(subscription, [29, 31].map { Date.new(2027, 3, it) })
    end

    it "lists the skipped day" do
      expect { run_task(organization.id, "2027-03-10") }
        .to output(a_string_including("timezone=Europe/Kyiv status=would_fill days=2027-03-30")).to_stdout
    end
  end

  context "without from_date" do
    it "starts at the daily usage history depth" do
      # 120 days before 2024-10-19
      expect { run_task(organization.id) }.to output(a_string_including("from 2024-06-21...")).to_stdout
    end
  end

  context "without an organization" do
    it "aborts" do
      expect { run_task }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    end
  end

  context "with an unknown organization" do
    it "aborts" do
      expect { run_task(SecureRandom.uuid) }.to raise_error(SystemExit).and output(/Organization not found/).to_stderr
    end
  end

  context "with an organization without revenue analytics" do
    let(:organization) { create(:organization, premium_integrations: []) }

    it "aborts" do
      expect { run_task(organization.id, from_date) }
        .to raise_error(SystemExit)
        .and output(/Revenue analytics is not enabled/).to_stderr
    end
  end

  context "with an invalid from_date" do
    it "aborts" do
      expect { run_task(organization.id, "2024-13-01") }
        .to raise_error(SystemExit)
        .and output(/Invalid from_date: 2024-13-01/).to_stderr
    end
  end
end
