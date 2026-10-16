# frozen_string_literal: true

require "rails_helper"

describe Clock::X402SignInNoncesCleanupJob do
  subject(:cleanup_job) { described_class }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    context "with nonces two days and two hours old" do
      let(:recent) { create(:x402_sign_in_nonce, created_at: 2.hours.ago) }

      before do
        create_list(:x402_sign_in_nonce, 2, created_at: 2.days.ago)
        recent
      end

      it "removes only the ones older than a day" do
        cleanup_job.perform_now
        expect(X402::SignInNonce.pluck(:id)).to eq([recent.id])
      end
    end

    context "with more expired nonces than one batch" do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 2)
        create_list(:x402_sign_in_nonce, 3, created_at: 2.days.ago)
      end

      it "removes them all" do
        expect { cleanup_job.perform_now }.to change(X402::SignInNonce, :count).to(0)
      end
    end
  end
end
