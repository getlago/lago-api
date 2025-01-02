# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeService, type: :service do
  subject(:compute_service) { described_class.new(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) do
    create(:subscription, :calendar, customer:, plan:, started_at: 1.year.ago, subscription_at: 1.year.ago)
  end

  let(:timestamp) { Time.zone.parse("2024-10-22 00:05:00") }
  let(:usage_date) { Date.parse("2024-10-21") }

  describe "#call" do
    it "creates a daily usage" do
      travel_to(timestamp) do
        expect { compute_service.call }.to change(DailyUsage, :count).by(1)

        daily_usage = DailyUsage.order(created_at: :asc).last
        expect(daily_usage).to have_attributes(
          organization_id: organization.id,
          customer_id: customer.id,
          subscription_id: subscription.id,
          external_subscription_id: subscription.external_id,
          usage: Hash,
          usage_diff: Hash,
          usage_date: Date.parse("2024-10-21")
        )
        expect(daily_usage.refreshed_at).to match_datetime(timestamp)
        expect(daily_usage.from_datetime).to match_datetime(timestamp.beginning_of_month)
        expect(daily_usage.to_datetime).to match_datetime(timestamp.end_of_month)
      end
    end

    context "when a daily usage already exists" do
      let(:existing_daily_usage) do
        create(:daily_usage, subscription:, organization:, customer:, usage_date:)
      end

      before { existing_daily_usage }

      it "returns the existing daily usage" do
        result = compute_service.call

        expect(result).to be_success
        expect(result.daily_usage).to eq(existing_daily_usage)
      end

      context "when the organization has a timezone" do
        let(:organization) { create(:organization, timezone: "America/Sao_Paulo") }

        let(:existing_daily_usage) do
          create(:daily_usage, subscription:, organization:, customer:, usage_date: usage_date - 4.hours)
        end

        it "takes the timezone into account" do
          result = compute_service.call

          expect(result).to be_success
          expect(result.daily_usage).to eq(existing_daily_usage)
        end
      end

      context "when the customer has a timezone" do
        let(:customer) { create(:customer, organization:, timezone: "America/Sao_Paulo") }

        let(:existing_daily_usage) do
          create(:daily_usage, subscription:, organization:, customer:, usage_date: usage_date - 4.hours)
        end

        it "takes the timezone into account" do
          result = compute_service.call

          expect(result).to be_success
          expect(result.daily_usage).to eq(existing_daily_usage)
        end
      end
    end

    context "when timestamp is on subscription billing day" do
      let(:subscription) do
        create(:subscription, :anniversary, customer:, plan:, started_at: 1.year.ago, subscription_at: 1.year.ago)
      end

      let(:timestamp) { subscription.subscription_at + 1.year }

      it "does not create a daily usage" do
        expect { compute_service.call }.not_to change(DailyUsage, :count)
      end
    end

    context "when subscription is terminated after the timestamp" do
      let(:subscription) do
        create(:subscription, :terminated, :calendar, customer:, plan:, started_at: 1.year.ago)
      end

      let(:timestamp) { subscription.terminated_at - 1.day }

      it "creates a daily usage" do
        travel_to("2024-11-24") do
          result = compute_service.call

          expect(result).to be_success

          daily_usage = result.daily_usage
          expect(daily_usage).to have_attributes(
            organization_id: organization.id,
            customer_id: customer.id,
            subscription_id: subscription.id,
            external_subscription_id: subscription.external_id,
            usage: Hash,
            usage_diff: Hash,
            usage_date: timestamp.to_date - 1.day
          )
          expect(daily_usage.refreshed_at).to match_datetime(timestamp)
          expect(daily_usage.from_datetime).to match_datetime(timestamp.beginning_of_month)
          expect(daily_usage.to_datetime).to match_datetime(subscription.terminated_at)
        end
      end
    end

    context "with customer timezone" do
      let(:customer) { create(:customer, organization:, timezone: "Australia/Sydney") }
      let(:timestamp) { Time.zone.parse("2024-10-21 15:05:00") }

      it "creates a daily usage with expected usage_date" do
        expect { compute_service.call }.to change(DailyUsage, :count).by(1)

        daily_usage = DailyUsage.order(created_at: :asc).last
        # Timestamp is 22 Oct 2024 02:05:00 AEDT
        expect(daily_usage.usage_date).to eq(Date.parse("2024-10-21"))
      end
    end
  end
end
