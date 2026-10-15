# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingPeriodDateDiff do
  describe "#date_diff_with_timezone" do
    subject(:date_diff_with_timezone) { record.date_diff_with_timezone(from_datetime, to_datetime) }

    let(:from_datetime) { Time.zone.parse("2023-08-31T23:10:00") }
    let(:to_datetime) { Time.zone.parse("2023-09-30T22:59:59") }
    let(:customer) { create(:customer, timezone: "Europe/Paris") }
    let(:record) { create(:subscription, customer:, plan:) }
    let(:plan) { create(:plan) }

    it "returns the number of days between the two datetimes in the customer timezone" do
      expect(date_diff_with_timezone).to eq(30)
    end

    context "with terminated and upgraded subscription" do
      let(:record) do
        create(
          :subscription,
          customer:,
          plan:,
          terminated_at: Time.zone.parse("2023-09-30T22:59:59")
        )
      end

      before do
        record.terminated!
        create(:subscription, customer:, plan:, previous_subscription_id: record.id)
      end

      it "removes the first day billed by the new subscription" do
        expect(date_diff_with_timezone).to eq(29)
      end
    end

    context "with a contract" do
      let(:record) { create(:contract, customer:, organization: customer.organization) }

      it "returns the number of days between the two datetimes in the customer timezone" do
        expect(date_diff_with_timezone).to eq(30)
      end
    end
  end
end
