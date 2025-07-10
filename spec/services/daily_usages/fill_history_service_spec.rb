# frozen_string_literal: true

# spec
RSpec.describe DailyUsages::FillHistoryService do
  let(:service) { described_class.new(subscription:, from_datetime:, to_datetime:) }

  describe "#to" do
    subject(:to) { service.to }

    let(:subscription) { create(:subscription, started_at: Time.current - 1.month) }
    let(:from_datetime) { Time.current - 2.weeks }
    let(:to_datetime) { nil }

    context "when subscription is terminated" do
      before { Subscriptions::TerminateService.call(subscription:) }

      context "when to_datetime is provided" do
        let(:to_datetime) { Time.current + 1.week }

        it "returns the to_datetime date" do
          expect(subject).to eq(subscription.terminated_at.to_date)
        end
      end

      context "when to_datetime is nil" do
        it "returns the current date" do
          expect(subject).to eq(Time.current.to_date)
        end
      end
    end

    context "when subscription is active" do
      context "when to_datetime is provided" do
        let(:to_datetime) { Time.current + 1.week }

        it "returns the to_datetime date" do
          expect(subject).to eq(to_datetime.to_date)
        end
      end

      context "when to_datetime is nil" do
        it "returns the current date" do
          expect(subject).to eq(Time.current.to_date)
        end
      end
    end
  end
end
