# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "invoices:backfill_metadata_updated_at" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["invoices:backfill_metadata_updated_at"] }

  let(:organization) { create(:organization) }

  before do
    Rake.application.rake_require("tasks/invoices")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  # Create an invoice whose updated_at is older than its metadata's updated_at
  # (reproduces the pre-fix historical state).
  def create_stale_invoice(org: organization, status: :finalized)
    invoice = create(:invoice, organization: org, status: status)
    create(:invoice_metadata, invoice: invoice, organization: org)
    invoice.update_column(:updated_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
    invoice
  end

  context "when there are no stale invoices" do
    it "reports 0 remaining and updates nothing" do
      expect { task.invoke(organization.id) }.to output(/Remaining stale invoices: 0/).to_stdout
    end
  end

  context "with one stale invoice" do
    let!(:invoice) { create_stale_invoice }

    it "bumps invoice.updated_at to the metadata timestamp" do
      metadata_updated_at = invoice.metadata.first.updated_at
      original_updated_at = invoice.updated_at

      expect { task.invoke(organization.id) }.to output(/Done/).to_stdout

      invoice.reload
      expect(invoice.updated_at).to be > original_updated_at
      expect(invoice.updated_at).to be_within(1.second).of(metadata_updated_at)
    end
  end

  context "with invoices in invisible statuses" do
    let!(:generating_invoice) { create_stale_invoice(status: :generating) }
    let!(:open_invoice) { create_stale_invoice(status: :open) }
    let!(:closed_invoice) { create_stale_invoice(status: :closed) }

    it "does not touch generating, open, or closed invoices" do
      original_updated_ats = [generating_invoice, open_invoice, closed_invoice].map(&:updated_at)

      task.invoke(organization.id)

      [generating_invoice, open_invoice, closed_invoice].each_with_index do |invoice, index|
        expect(invoice.reload.updated_at).to be_within(1.second).of(original_updated_ats[index])
      end
    end
  end

  context "with invoices in a different organization" do
    let(:other_organization) { create(:organization) }
    let!(:other_invoice) { create_stale_invoice(org: other_organization) }

    it "does not touch invoices outside the target organization" do
      original_updated_at = other_invoice.updated_at

      task.invoke(organization.id)

      expect(other_invoice.reload.updated_at).to be_within(1.second).of(original_updated_at)
    end
  end

  context "when run twice" do
    before { create_stale_invoice }

    it "is idempotent: the second run updates zero rows" do
      task.invoke(organization.id)
      task.reenable

      expect { task.invoke(organization.id) }.to output(/Batch updated: 0 rows/).to_stdout
    end
  end

  context "with multiple stale invoices across multiple batches" do
    let!(:stale_invoices) { Array.new(3) { create_stale_invoice } }

    before do
      ENV["BATCH_SIZE"] = "1"
      ENV["TOTAL_LIMIT"] = "10"
    end

    after do
      ENV.delete("BATCH_SIZE")
      ENV.delete("TOTAL_LIMIT")
    end

    it "processes every stale invoice across iterations and reports zero remaining" do
      expect { task.invoke(organization.id) }.to output(/Remaining stale invoices: 0/).to_stdout

      stale_invoices.each do |invoice|
        metadata_updated_at = invoice.metadata.first.updated_at
        expect(invoice.reload.updated_at).to be_within(1.second).of(metadata_updated_at)
      end
    end
  end

  context "with TOTAL_LIMIT set below the stale count" do
    before do
      2.times { create_stale_invoice }
      ENV["BATCH_SIZE"] = "1"
      ENV["TOTAL_LIMIT"] = "1"
    end

    after do
      ENV.delete("BATCH_SIZE")
      ENV.delete("TOTAL_LIMIT")
    end

    it "stops processing once the cap is reached" do
      expect { task.invoke(organization.id) }.to output(/Remaining stale invoices: 1/).to_stdout
    end
  end

  context "without an organization_id argument" do
    it "aborts with a usage message" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Missing organization_id argument/).to_stderr
    end
  end
end
