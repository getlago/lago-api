# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:recurring_aggregation_snapshots:audit" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["recipes:recurring_aggregation_snapshots:audit"] }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:, customer: create(:customer, organization:)) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:csv_path) { Rails.root.join("tmp", "recurring_snapshots_audit_spec_#{SecureRandom.hex(4)}.csv").to_s }
  let(:to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }
  let(:watermark) { Time.zone.parse("2026-10-01T00:10:00") }

  let(:audit) { audit_result(rows: [row]) }
  let(:row) { build_row(stored_units: BigDecimal(10)) }

  def build_row(stored_units:, bounded: true)
    values = RecurringAggregationSnapshots::AuditService::Values
    RecurringAggregationSnapshots::AuditService::Row.new(
      charge_id: charge.id,
      billable_metric_code: billable_metric.code,
      charge_filter_id: nil,
      grouped_by: {},
      to_datetime:,
      watermark:,
      bounded:,
      stored: values.new(units: stored_units, events_count: 4),
      recomputed: values.new(units: BigDecimal(10), events_count: 4)
    )
  end

  def audit_result(rows:, snapshot_charges_count: 1, charges_without_marker: [], charges_without_invoice: [])
    RecurringAggregationSnapshots::AuditService::Result.new.tap do
      it.rows = rows
      it.differences = rows.select(&:different?)
      it.audited_charges_count = 1
      it.snapshot_charges_count = snapshot_charges_count
      it.charges_without_marker = charges_without_marker
      it.charges_without_invoice = charges_without_invoice
    end
  end

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  before do
    Rake.application.rake_require("tasks/recipes/recurring_aggregation_snapshots_audit")
    Rake::Task.define_task(:environment)
    task.reenable

    allow(RecurringAggregationSnapshots::AuditService).to receive(:call).and_return(audit)
  end

  after { FileUtils.rm_f(csv_path) }

  context "with listed subscriptions" do
    before { stub_stdin(organization.id, "y", subscription.id, csv_path) }

    it "audits the given subscription and writes one CSV row per leaf" do
      expect { task.invoke }.to output(/The stored snapshots match their events/).to_stdout

      expect(RecurringAggregationSnapshots::AuditService).to have_received(:call).with(subscription:)

      csv = CSV.read(csv_path)
      expect(csv.first).to eq(RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS)
      expect(csv.second).to eq(
        [
          subscription.id,
          subscription.external_id,
          charge.id,
          billable_metric.code,
          nil,
          "{}",
          "2026-09-30T23:59:59.000000Z",
          "2026-10-01T00:10:00.000000Z",
          "true",
          "10.0",
          "10.0",
          "4",
          "4"
        ]
      )
    end

    context "when a leaf differs" do
      let(:row) { build_row(stored_units: BigDecimal(12)) }

      it "reports the mismatch" do
        expect { task.invoke }.to output(/Mismatches detected, investigate the write path/).to_stdout
      end
    end

    context "when only a weighted sum leaf differs" do
      let(:row) { build_row(stored_units: BigDecimal(12), bounded: false) }

      it "counts it apart from the mismatches" do
        expect { task.invoke }.to output(/weighted sum differences:\s+1.*The stored snapshots match their events/m).to_stdout
      end
    end

    context "when a charge has no period marker" do
      let(:audit) { audit_result(rows: [row], charges_without_marker: [charge.id]) }

      it "reports the mismatch" do
        expect { task.invoke }.to output(/no default bucket row.*Mismatches detected/m).to_stdout
      end
    end

    context "when a charge has no invoice for its period" do
      let(:audit) { audit_result(rows: [], charges_without_invoice: [charge.id]) }

      it "reports the subscription as incomplete" do
        expect { task.invoke }.to output(
          /\[INCOMPLETE\].*no invoice for its latest period.*charges without period invoice: 1.*were not audited/m
        ).to_stdout
      end
    end

    context "when no subscription has a snapshot" do
      let(:audit) { audit_result(rows: [], snapshot_charges_count: 0) }

      it "says the run proves nothing" do
        expect { task.invoke }.to output(/this run says nothing about the write path/).to_stdout
      end
    end
  end

  context "when every audit fails" do
    before do
      allow(RecurringAggregationSnapshots::AuditService).to receive(:call)
        .and_return(BaseService::Result.new.service_failure!(code: "boom", message: "boom"))
      stub_stdin(organization.id, "y", subscription.id, csv_path)
    end

    it "says nothing could be audited" do
      expect { task.invoke }.to output(/No subscription could be audited/).to_stdout
    end
  end

  context "without listed subscriptions" do
    let(:other_subscription) { create(:subscription, organization:, customer: subscription.customer) }

    before do
      other_subscription
      create(:subscription, customer: create(:customer))
      stub_stdin(organization.id, "y", "", "1", csv_path)
    end

    it "samples the active subscriptions of the organization" do
      expect { task.invoke }.to output(/Organization has 2 active subscription\(s\)/).to_stdout

      expect(RecurringAggregationSnapshots::AuditService).to have_received(:call).once
      expect(RecurringAggregationSnapshots::AuditService).to have_received(:call)
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
