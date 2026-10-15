# frozen_string_literal: true

require "rails_helper"

describe X402::Settlements::ReconcileJob, job: true do
  subject(:job) { described_class }

  let(:settlement) { create(:x402_settlement, :pending) }

  before { allow(X402::Settlements::ReconcileService).to receive(:call!) }

  it_behaves_like "a unique job" do
    let(:job_args) { [settlement] }
  end

  it "forwards the settlement to the service" do
    job.perform_now(settlement)

    expect(X402::Settlements::ReconcileService).to have_received(:call!).with(settlement:)
  end

  it "runs on the providers queue" do
    expect(job.new(settlement).queue_name).to eq("providers")
  end

  context "with the payments worker enabled" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SIDEKIQ_PAYMENTS").and_return("true")
    end

    it "runs on the payments queue" do
      expect(job.new(settlement).queue_name).to eq("payments")
    end
  end
end
