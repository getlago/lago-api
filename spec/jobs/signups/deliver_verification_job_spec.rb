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

  {
    "a timeout" => Net::OpenTimeout,
    "a refused connection" => Errno::ECONNREFUSED,
    "a reset connection" => Errno::ECONNRESET,
    "an unreachable host" => Errno::EHOSTUNREACH,
    "a connect timeout" => Errno::ETIMEDOUT,
    "an unreachable network" => Errno::ENETUNREACH,
    "a DNS failure" => SocketError,
    "a failed STARTTLS handshake" => OpenSSL::SSL::SSLError,
    "a busy relay" => Net::SMTPServerBusy.new("busy")
  }.each do |reason, error|
    context "when delivery fails on #{reason}" do
      before do
        allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(error) # rubocop:disable RSpec/AnyInstance
      end

      it "retries later" do
        described_class.perform_now(pending_signup.id)

        expect(described_class).to have_been_enqueued.with(pending_signup.id)
      end
    end
  end

  context "when the SMTP server refuses the message for good" do
    before do
      allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(Net::SMTPFatalError.new("fatal")) # rubocop:disable RSpec/AnyInstance
    end

    it "does not retry" do
      expect { described_class.perform_now(pending_signup.id) }.to raise_error(Net::SMTPFatalError)
      expect(described_class).not_to have_been_enqueued
    end
  end

  context "when the relay is still busy on the 10th attempt" do
    let(:job) { described_class.new(pending_signup.id) }

    before do
      allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(Net::SMTPServerBusy.new("busy")) # rubocop:disable RSpec/AnyInstance
      # 9 retries waited n**4 + 2 s for n = 1..9 (15_351 s), plus up to 15% jitter: 4.3 to 4.9 h after Step 1
      job.exception_executions["[Net::SMTPServerBusy]"] = 9
    end

    it "gives up, so the job reaches the dead set" do
      expect { job.perform_now }.to raise_error(Net::SMTPServerBusy)
      expect(described_class).not_to have_been_enqueued
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
