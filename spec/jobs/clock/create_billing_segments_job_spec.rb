# frozen_string_literal: true

require "rails_helper"

describe Clock::CreateBillingSegmentsJob, job: true do
  it "keeps the queued job signature and does nothing" do
    expect { described_class.perform_now }.not_to have_enqueued_job
  end
end
