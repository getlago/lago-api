# frozen_string_literal: true

require 'rails_helper'

describe Clock::RefreshWalletsOngoingBalanceJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:wallets) { create_list(:wallet, 3) }

    before do
      wallets
    end

    context 'when freemium' do
      it 'does not enqueue a refresh job' do
        described_class.perform_now
        expect(Wallets::RefreshOngoingBalanceJob).not_to have_been_enqueued
      end
    end

    context 'when premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues a refresh job for each wallets' do
        described_class.perform_now
        expect(Wallets::RefreshOngoingBalanceJob).to have_been_enqueued.with(wallets.first)
        expect(Wallets::RefreshOngoingBalanceJob).to have_been_enqueued.with(wallets.second)
        expect(Wallets::RefreshOngoingBalanceJob).to have_been_enqueued.with(wallets.third)
      end

      context 'when not active' do
        let(:wallets) { [create(:wallet, :terminated)] }

        it 'does not enqueue a refresh job' do
          described_class.perform_now
          expect(Wallets::RefreshOngoingBalanceJob).not_to have_been_enqueued
        end
      end
    end
  end
end
