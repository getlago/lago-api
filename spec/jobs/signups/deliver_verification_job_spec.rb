# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::DeliverVerificationJob do
  let(:pending_signup) { create(:pending_signup) }

  include_context "with self-serve enabled"

  it "delivers the attempt's email" do
    allow(Signups::DeliverVerificationService).to receive(:call!)

    described_class.perform_now(pending_signup.id)

    expect(Signups::DeliverVerificationService).to have_received(:call!).with(pending_signup:)
  end

  it "does nothing for a purged attempt" do
    expect { described_class.perform_now(SecureRandom.uuid) }.not_to change { ActionMailer::Base.deliveries.count }
  end

  it "takes the attempt id as its only argument" do
    expect { described_class.perform_later(pending_signup.id) }.to have_enqueued_job(described_class).with(pending_signup.id)
  end

  it "sends the email itself, without a SendEmailJob" do
    expect { described_class.perform_now(pending_signup.id) }.to change { ActionMailer::Base.deliveries.count }.by(1)
    expect(SendEmailJob).not_to have_been_enqueued
  end

  context "when delivery times out" do
    before do
      allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(Net::OpenTimeout) # rubocop:disable RSpec/AnyInstance
    end

    it "retries later" do
      described_class.perform_now(pending_signup.id)

      expect(described_class).to have_been_enqueued.with(pending_signup.id)
    end
  end

  context "when self-serve is turned off or signups are paused" do
    it "sends nothing" do
      [{"LAGO_SELF_SERVE_ENABLED" => "false"}, {"LAGO_DISABLE_SIGNUP" => "true"}].each do |env|
        stub_const("ENV", ENV.to_h.merge(env))

        expect { described_class.perform_now(pending_signup.id) }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end
end
