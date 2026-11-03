# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:backfill_customers_payment_term" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:backfill_customers_payment_term"] }
  let(:job) { DatabaseMigrations::BackfillCustomersPaymentTermJob }

  let(:customer) { create(:customer) }

  before do
    Rake.application.rake_require("tasks/migrations/customers_payment_term")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  it "enqueues the backfill from the beginning" do
    expect { task.invoke }.to output(/from the beginning/).to_stdout

    expect(job).to have_been_enqueued.with(nil)
  end

  it "fills the customers missing their term" do
    customer.update_columns(net_payment_term: 45, payment_term: nil) # rubocop:disable Rails/SkipsModelValidations

    expect { perform_enqueued_jobs { task.invoke } }.to output(/Enqueued/).to_stdout

    expect(customer.reload.payment_term).to eq("term_type" => "net", "days" => 45)
  end

  context "when START_AFTER is set" do
    around do |example|
      ENV["START_AFTER"] = customer.id
      example.run
    ensure
      ENV["START_AFTER"] = nil
    end

    it "enqueues the backfill from that customer" do
      expect { task.invoke }.to output(/after customer #{customer.id}/).to_stdout

      expect(job).to have_been_enqueued.with(customer.id)
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
