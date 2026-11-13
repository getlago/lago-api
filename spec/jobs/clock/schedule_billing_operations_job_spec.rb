# frozen_string_literal: true

require "rails_helper"

describe Clock::ScheduleBillingOperationsJob, job: true do
  it "does nothing for already-enqueued legacy ticks" do
    expect { described_class.perform_now }.not_to have_enqueued_job
  end
end
