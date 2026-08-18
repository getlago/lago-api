# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionBillingPeriod, type: :model do
  subject(:billing_period) { build(:subscription_billing_period) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription)
      expect(subject).to belong_to(:customer)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:scope_type)
      expect(subject).to validate_inclusion_of(:scope_type).in_array(described_class::SCOPE_TYPES)
      expect(subject).to validate_presence_of(:period_from)
      expect(subject).to validate_presence_of(:period_to)
    end

    describe "period_to validation" do
      it "rejects a period_to before period_from" do
        billing_period.period_from = Time.current
        billing_period.period_to = 1.day.ago

        expect(billing_period).not_to be_valid
        expect(billing_period.errors.where(:period_to, :must_be_after_period_from)).to be_present
      end

      it "rejects a period_to equal to period_from" do
        now = Time.current
        billing_period.period_from = now
        billing_period.period_to = now

        expect(billing_period).not_to be_valid
      end
    end
  end

  describe "Scopes" do
    let(:subscription) { create(:subscription) }
    let(:period) do
      create(
        :subscription_billing_period,
        subscription:,
        period_from: Time.utc(2024, 3, 1),
        period_to: Time.utc(2024, 3, 31).end_of_day
      )
    end

    describe ".covering" do
      it "matches inside the period and on either bound" do
        period

        expect(described_class.covering(Time.utc(2024, 3, 15))).to eq([period])
        expect(described_class.covering(period.period_from)).to eq([period])
        expect(described_class.covering(period.period_to)).to eq([period])
      end

      it "does not match outside the period" do
        period

        expect(described_class.covering(Time.utc(2024, 2, 29))).to be_empty
        expect(described_class.covering(Time.utc(2024, 4, 1))).to be_empty
      end
    end

    describe ".expired" do
      it "matches periods that have ended" do
        period

        expect(described_class.expired(Time.utc(2024, 4, 1))).to eq([period])
        expect(described_class.expired(Time.utc(2024, 3, 15))).to be_empty
      end
    end
  end

  describe "the overlap constraint" do
    let(:subscription) { create(:subscription) }

    before do
      # The constraint is deferred to commit so the convergent write can transiently overlap, and a
      # spec runs inside a transaction that never commits. Checked immediately here instead.
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")

      create(
        :subscription_billing_period,
        subscription:,
        period_from: Time.utc(2024, 3, 1),
        period_to: Time.utc(2024, 3, 31).end_of_day
      )
    end

    it "rejects an overlapping period for the same scope" do
      expect do
        create(
          :subscription_billing_period,
          subscription:,
          period_from: Time.utc(2024, 3, 15),
          period_to: Time.utc(2024, 4, 15).end_of_day
        )
      end.to raise_error(ActiveRecord::StatementInvalid, /no_overlapping_periods/)
    end

    it "accepts a period that starts when the previous one ends" do
      expect do
        create(
          :subscription_billing_period,
          subscription:,
          period_from: Time.utc(2024, 4, 1),
          period_to: Time.utc(2024, 4, 30).end_of_day
        )
      end.not_to raise_error
    end

    it "accepts an overlapping period for another scope" do
      expect do
        create(
          :subscription_billing_period,
          subscription: create(:subscription),
          period_from: Time.utc(2024, 3, 15),
          period_to: Time.utc(2024, 4, 15).end_of_day
        )
      end.not_to raise_error
    end
  end
end
