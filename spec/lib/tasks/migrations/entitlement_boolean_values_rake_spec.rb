# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:backfill_entitlement_boolean_values" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:backfill_entitlement_boolean_values"] }
  let(:job) { DatabaseMigrations::BackfillEntitlementBooleanValuesJob }

  let(:privilege) { create(:privilege, value_type: "boolean") }
  let(:entitlement_value) { create(:entitlement_value, privilege:, value: "t") }

  before do
    Rake.application.rake_require("tasks/migrations/entitlement_boolean_values")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  it "enqueues the backfill from the beginning" do
    expect { task.invoke }.to output(/from the beginning/).to_stdout

    expect(job).to have_been_enqueued.with(nil)
  end

  it "rewrites the boolean values stored as t" do
    entitlement_value

    expect { perform_enqueued_jobs { task.invoke } }.to output(/Enqueued/).to_stdout

    expect(entitlement_value.reload.read_attribute(:value)).to eq("true")
  end

  context "when START_AFTER is set" do
    around do |example|
      ENV["START_AFTER"] = entitlement_value.id
      example.run
    ensure
      ENV["START_AFTER"] = nil
    end

    it "enqueues the backfill from that value" do
      expect { task.invoke }.to output(/after entitlement value #{entitlement_value.id}/).to_stdout

      expect(job).to have_been_enqueued.with(entitlement_value.id)
    end
  end

  context "when the backfill is already enqueued" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
    ensure
      ActiveJob::Uniqueness.unlock!(job_class_name: job.name)
      ActiveJob::Uniqueness.test_mode!
    end

    before { job.perform_later(nil) }

    it "aborts instead of reporting it enqueued" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Not enqueued/).to_stderr

      expect(job).to have_been_enqueued.once
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
