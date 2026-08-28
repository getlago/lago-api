# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contract do
  subject(:contract) { build(:contract) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", active: "active", terminated: "terminated", canceled: "canceled")
      expect(subject).to define_enum_for(:billing_time)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(calendar: "calendar", anniversary: "anniversary")
    end
  end

  describe "associations" do
    it do
      expect(contract).to belong_to(:organization)
      expect(contract).to belong_to(:customer)
      expect(contract).to belong_to(:plan).optional
      expect(contract).to have_many(:applied_rate_cards).class_name("ContractRateCard")
    end

    it "resolves a discarded customer and plan" do
      customer = create(:customer)
      plan = create(:plan, organization: customer.organization)
      contract = create(:contract, customer:, plan:, organization: customer.organization)

      customer.discard!
      plan.discard!

      expect(contract.reload.customer).to eq(customer)
      expect(contract.plan).to eq(plan)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:external_id) }

    it "rejects an ended_at before started_at" do
      contract = build(:contract, started_at: Time.zone.parse("2026-02-15"), ended_at: Time.zone.parse("2026-02-01"))

      expect(contract).not_to be_valid
      expect(contract.errors.where(:ended_at, :must_be_after_started_at)).to be_present
    end
  end

  describe "#effective_billing_anchor_date" do
    it "prefers the explicit anchor" do
      contract = build(:contract, billing_anchor_date: Date.new(2026, 1, 1), started_at: Time.zone.parse("2026-02-15"))

      expect(contract.effective_billing_anchor_date).to eq(Date.new(2026, 1, 1))
    end

    it "falls back to the day the contract starts" do
      contract = build(:contract, billing_anchor_date: nil, started_at: Time.zone.parse("2026-02-15"))
      expect(contract.effective_billing_anchor_date).to eq(Date.new(2026, 2, 15))

      upcoming = build(:contract, :pending, billing_anchor_date: nil, started_at: Time.zone.parse("2026-03-01"))
      expect(upcoming.effective_billing_anchor_date).to eq(Date.new(2026, 3, 1))
    end
  end
end
