# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:backfill_progressive_billing_trigger" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:backfill_progressive_billing_trigger"] }

  before do
    Rake.application.rake_require("tasks/migrations/progressive_billing_trigger")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  it "enqueues the backfill" do
    expect { task.invoke }.to output(/Enqueued/).to_stdout

    expect(DatabaseMigrations::BackfillProgressiveBillingTriggerJob).to have_been_enqueued.with(no_args)
  end
end
