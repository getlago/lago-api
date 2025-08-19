# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::FillHistoryService do
  let(:service) { described_class.new(subscription:, from_date:, to_date:) }

  describe "#to" do
    subject(:to) { service.to }

    let(:subscription) { create(:subscription, started_at: Time.current - 1.month) }
    let(:from_date) { Time.zone.today - 2.weeks }
    let(:to_date) { nil }

    context "when subscription is terminated" do
      before { Subscriptions::TerminateService.call(subscription:) }

      let(:to_date) { Time.zone.today + 1.week }

      it "returns the terminated_at date" do
        expect(subject).to eq(subscription.terminated_at.to_date)
      end
    end

    context "when subscription is active" do
      context "when to_date is provided" do
        let(:to_date) { Time.zone.today + 1.week }

        it "returns the to_date date" do
          expect(subject).to eq(to_date)
        end
      end

      context "when to_date is nil" do
        it "returns yesterday" do
          expect(subject).to eq(Time.zone.yesterday)
        end
      end
    end
  end
end
