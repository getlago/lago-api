# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:recurring_aggregation_snapshots:audit" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["recipes:recurring_aggregation_snapshots:audit"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }
  let(:csv_path) { Rails.root.join("tmp", "recurring_snapshots_audit_spec_#{SecureRandom.hex(4)}.csv").to_s }

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  before do
    Rake.application.rake_require("tasks/recipes/recurring_aggregation_snapshots_audit")
    Rake::Task.define_task(:environment)
    task.reenable

    create(:invoice_subscription, subscription:, invoice:, charges_to_datetime: to_datetime)
    create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, to_datetime:, units: 10, events_count: 4)
    create(:charge_fee, organization:, invoice:, subscription:, charge:, total_aggregated_units: 12, events_count: 4)
  end

  after { FileUtils.rm_f(csv_path) }

  context "with listed subscriptions" do
    before { stub_stdin(organization.id, "y", subscription.id, csv_path) }

    it "writes one CSV row per differing leaf" do
      expect { task.invoke }.to output(/1 leaf\/leaves, 1 differing, 0 period\(s\) without invoice/).to_stdout

      expect(CSV.read(csv_path)).to eq(
        [
          RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS,
          [
            subscription.id,
            subscription.external_id,
            charge.id,
            nil,
            "{}",
            "2026-09-30T23:59:59.000000Z",
            "10.0",
            "12.0",
            "4",
            "4"
          ]
        ]
      )
    end
  end

  context "without listed subscriptions" do
    let(:other_subscription) { create(:subscription, organization:, customer:) }

    before do
      other_subscription
      create(:subscription, customer: create(:customer))
      stub_stdin(organization.id, "y", "", "1", csv_path)
      allow(RecurringAggregationSnapshots::AuditService).to receive(:call!).and_call_original
    end

    it "samples the active subscriptions of the organization" do
      expect { task.invoke }.to output(/Organization has 2 active subscription\(s\)/).to_stdout

      expect(RecurringAggregationSnapshots::AuditService).to have_received(:call!).once
      expect(RecurringAggregationSnapshots::AuditService).to have_received(:call!)
        .with(subscription: satisfy { [subscription, other_subscription].include?(it) })
    end
  end

  context "with an invalid sample size" do
    before { stub_stdin(organization.id, "y", "", "abc") }

    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Organization has/).to_stdout
    end
  end
end
