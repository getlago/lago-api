# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:backfill_invoices_search_terms" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:backfill_invoices_search_terms"] }
  let(:job) { DatabaseMigrations::BackfillInvoicesSearchTermsJob }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, name: "Acme Inc") }

  before do
    Rake.application.rake_require("tasks/migrations/invoices_search_terms")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  it "enqueues the backfill from the beginning" do
    expect { task.invoke }.to output(/from the beginning/).to_stdout

    expect(job).to have_been_enqueued.with(nil)
  end

  it "fills the invoices missing their search terms" do
    invoice = create(:invoice, organization:, customer:, number: "INV-001")
    Invoice.where(id: invoice.id).update_all(search_terms: nil) # rubocop:disable Rails/SkipsModelValidations

    expect { perform_enqueued_jobs { task.invoke } }.to output(/Enqueued/).to_stdout

    expect(invoice.reload.search_terms).to include("INV-001", "Acme Inc")
  end

  context "when START_AFTER is set" do
    let(:invoice) { create(:invoice, organization:, customer:) }

    around do |example|
      ENV["START_AFTER"] = invoice.id
      example.run
    ensure
      ENV["START_AFTER"] = nil
    end

    it "enqueues the backfill from that invoice" do
      expect { task.invoke }.to output(/after invoice #{invoice.id}/).to_stdout

      expect(job).to have_been_enqueued.with(invoice.id)
    end
  end

  context "when START_AFTER is unknown" do
    around do |example|
      ENV["START_AFTER"] = SecureRandom.uuid
      example.run
    ensure
      ENV["START_AFTER"] = nil
    end

    it "aborts without enqueuing the backfill" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Unknown START_AFTER/).to_stderr

      expect(job).not_to have_been_enqueued
    end
  end
end
