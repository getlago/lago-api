# frozen_string_literal: true

require 'rails_helper'

describe Clock::RefreshWalletsCreditsJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:wallet) { create(:wallet) }

    before do
      wallet
      allow(Wallets::RefreshCreditsService).to receive(:call)
    end

    it 'calls the refresh service' do
      described_class.perform_now
      expect(Wallets::RefreshCreditsJob).to have_been_enqueued.with(wallet)
    end

    context 'when not active' do
      let(:wallet) { create(:wallet, :terminated) }

      it 'does not call the refresh service' do
        described_class.perform_now
        expect(Wallets::RefreshCreditsJob).not_to have_been_enqueued.with(wallet)
      end
    end
  end
end
