# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "migrations:rechain_daily_usage_diffs" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:rechain_daily_usage_diffs"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :terminated, organization:, customer:, terminated_at:) }

  let(:terminated_at) { Time.zone.parse("2025-02-03T15:00:00Z") }
  let(:period_start) { Time.zone.parse("2025-02-01T00:00:00Z") }
  let(:period_end) { Time.zone.parse("2025-02-28T23:59:59Z") }

  let(:second_day_end) { period_end }
  let(:second_day_diff) { usage(1000) }
  # Written from the terminating invoice before the fix: diffed against nothing, so it holds the whole period
  let(:termination_diff) { usage(3000) }

  let(:second_day) do
    create_daily_usage(subscription, Date.new(2025, 2, 2), second_day_end, usage(2000), usage_diff: second_day_diff)
  end
  let(:termination_row) do
    create_daily_usage(subscription, Date.new(2025, 2, 3), terminated_at, usage(3000), usage_diff: termination_diff)
  end

  before do
    # The previous period has another start: the first row of February is not diffed against it
    create_daily_usage(
      subscription, Date.new(2025, 1, 31), Time.zone.parse("2025-01-31T23:59:59Z"), usage(4000),
      from_datetime: Time.zone.parse("2025-01-01T00:00:00Z")
    )
    create_daily_usage(subscription, Date.new(2025, 2, 1), period_end, usage(1000))
    second_day
    termination_row

    Rake.application.rake_require("tasks/migrations/rechain_daily_usage_diffs")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  # One event of 1 unit at 10 EUR a day
  def usage(amount_cents)
    {
      "currency" => "EUR",
      "amount_cents" => amount_cents,
      "taxes_amount_cents" => 0,
      "total_amount_cents" => amount_cents,
      "charges_usage" => [
        {
          "charge" => {"lago_id" => "charge-a"},
          "amount_cents" => amount_cents,
          "units" => "#{amount_cents / 1000}.0",
          "events_count" => amount_cents / 1000,
          "filters" => [],
          "grouped_usage" => []
        }
      ]
    }
  end

  def create_daily_usage(subscription, usage_date, to_datetime, usage, usage_diff: usage, from_datetime: period_start)
    create(
      :daily_usage,
      organization: subscription.organization,
      customer: subscription.customer,
      subscription:,
      from_datetime:,
      to_datetime:,
      usage_date:,
      usage:,
      usage_diff:
    )
  end

  def entry_line(daily_usage, status:, amounts:)
    "daily_usage=#{daily_usage.id} organization=#{daily_usage.organization_id} subscription=#{daily_usage.subscription_id} " \
      "usage_date=#{daily_usage.usage_date.iso8601} status=#{status} amount_cents=#{amounts}"
  end

  context "without DRY_RUN" do
    it "lists the termination row and writes nothing" do
      expect { task.invoke }
        .to output(
          a_string_including(
            "[DRY RUN] (organization: all)",
            entry_line(termination_row, status: :would_recompute, amounts: "3000->1000"),
            "Done [DRY RUN]. Rows to recompute: 1."
          )
        ).to_stdout
        .and not_change { DailyUsage.order(:id).pluck(:usage_diff) }
    end
  end

  context "when DRY_RUN is false" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "diffs the termination row against the row before it and leaves the other rows" do
      expect { task.invoke }
        .to output(
          a_string_including(
            "[LIVE]",
            entry_line(termination_row, status: :recomputed, amounts: "3000->1000"),
            "Done [LIVE]. Rows recomputed: 1."
          )
        ).to_stdout
        .and not_change { DailyUsage.where.not(id: termination_row.id).order(:id).pluck(:usage_diff) }

      expect(termination_row.reload.usage_diff).to eq(usage(1000)) # 3000 at the termination - 2000 on Feb 2
    end

    it "changes nothing on a second run" do
      expect { task.invoke }.to output.to_stdout
      task.reenable

      expect { task.invoke }
        .to output(a_string_including("Done [LIVE]. Rows recomputed: 0.")).to_stdout
        .and not_change { termination_row.reload.usage_diff }
    end

    context "when the row before the termination row also ends at the termination" do
      # The daily job of a day before the termination, run after it, reads the period's end at the termination
      let(:second_day_end) { terminated_at }
      let(:second_day_diff) { usage(2000) }
      let(:termination_diff) { usage(1000) }

      it "recomputes the row whose previous row ends at another time only" do
        expect { task.invoke }
          .to output(
            a_string_including(
              entry_line(second_day, status: :recomputed, amounts: "2000->1000"),
              "Done [LIVE]. Rows recomputed: 1."
            )
          ).to_stdout
          .and not_change { termination_row.reload.usage_diff }

        expect(second_day.reload.usage_diff).to eq(usage(1000)) # 2000 on Feb 2 - 1000 on Feb 1
      end
    end
  end

  context "with an organization_id" do
    let(:other_subscription) do
      other_organization = create(:organization)
      create(:subscription, :terminated, organization: other_organization, customer: create(:customer, organization: other_organization), terminated_at:)
    end

    let(:other_termination_row) do
      create_daily_usage(other_subscription, Date.new(2025, 2, 3), terminated_at, usage(3000))
    end

    before do
      create_daily_usage(other_subscription, Date.new(2025, 2, 2), period_end, usage(2000))
      other_termination_row
    end

    it "lists the rows of that organization only" do
      expect { task.invoke(organization.id) }
        .to output(
          a_string_including(
            "(organization: #{organization.id})",
            entry_line(termination_row, status: :would_recompute, amounts: "3000->1000"),
            "Rows to recompute: 1."
          )
        ).to_stdout
    end
  end

  context "when the organization does not exist" do
    it "aborts" do
      expect { task.invoke(SecureRandom.uuid) }.to raise_error(SystemExit).and output(/Organization not found/).to_stderr
    end
  end

  context "when the diff of a row fails" do
    before do
      allow(DailyUsages::ComputeDiffService).to receive(:call!).and_raise(StandardError, "unexpected usage")
    end

    it "stops and names the row" do
      expect { task.invoke }
        .to raise_error(SystemExit)
        .and output(a_string_including("Failed on daily usage #{termination_row.id}: StandardError: unexpected usage")).to_stderr
        .and output(a_string_including("[DRY RUN]")).to_stdout
    end
  end
end
