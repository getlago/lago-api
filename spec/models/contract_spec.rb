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

    describe "live external id uniqueness (database)" do
      it "allows one pending and one active but never two of either" do
        organization = create(:organization)
        customer = create(:customer, organization:)
        create(:contract, organization:, customer:, external_id: "c-1")
        create(:contract, :pending, organization:, customer:, external_id: "c-1")

        expect { create(:contract, organization:, customer:, external_id: "c-1") }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "does not constrain finished contracts" do
        organization = create(:organization)
        customer = create(:customer, organization:)
        create(:contract, :terminated, organization:, customer:, external_id: "c-1")
        create(:contract, :terminated, organization:, customer:, external_id: "c-1")

        expect { create(:contract, organization:, customer:, external_id: "c-1") }.not_to raise_error
      end
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

    it "derives the fallback in the customer's timezone" do
      customer = create(:customer, timezone: "America/Los_Angeles")
      contract = build(
        :contract,
        customer:,
        organization: customer.organization,
        billing_anchor_date: nil,
        started_at: Time.zone.parse("2026-10-01T02:00:00Z")
      )

      expect(contract.effective_billing_anchor_date).to eq(Date.new(2026, 9, 30))
    end
  end

  describe "#editable?" do
    it "is true only while the contract is pending" do
      expect(build(:contract, :pending).editable?).to be(true)
      expect(build(:contract, status: :active).editable?).to be(false)
      expect(build(:contract, :terminated).editable?).to be(false)
      expect(build(:contract, :canceled).editable?).to be(false)
    end
  end

  describe "#currency" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, currency: "USD") }

    it "prefers the plan currency over the customer currency" do
      plan = create(:plan, organization:, amount_currency: "EUR")
      expect(build(:contract, organization:, customer:, plan:).currency).to eq("EUR")
    end

    it "uses the customer currency for a plan-less contract" do
      expect(build(:contract, organization:, customer:, plan: nil).currency).to eq("USD")
    end

    it "falls back to the organization default when the customer has none" do
      no_currency = create(:customer, organization:, currency: nil)
      contract = build(:contract, organization:, customer: no_currency, plan: nil)

      expect(contract.currency).to eq(organization.default_currency)
    end
  end

  describe "#default_rate_card_lifecycle" do
    it "seeds the window, anchor and clock from the contract" do
      customer = create(:customer, timezone: "America/Los_Angeles")
      contract = build(:contract, customer:, organization: customer.organization, started_at: Time.zone.parse("2026-10-01T02:00:00Z"))

      lifecycle = contract.default_rate_card_lifecycle

      expect(lifecycle[:effective_date]).to eq(Date.new(2026, 9, 30))
      expect(lifecycle[:billing_anchor_date]).to eq(contract.effective_billing_anchor_date)
      expect(lifecycle[:next_billing_at]).to eq(contract.started_at)
    end

    it "prefers an explicit anchor" do
      contract = build(:contract, started_at: Time.zone.parse("2026-02-15"))

      expect(contract.default_rate_card_lifecycle(billing_anchor_date: Date.new(2026, 3, 1))[:billing_anchor_date]).to eq(Date.new(2026, 3, 1))
    end
  end

  describe "Scopes" do
    describe ".live" do
      it "returns only pending and active contracts" do
        pending = create(:contract, :pending)
        active = create(:contract)
        create(:contract, :terminated)
        create(:contract, :canceled)

        expect(described_class.live).to match_array([pending, active])
      end
    end

    describe ".live_by_external_id" do
      let(:organization) { create(:organization) }

      it "resolves to the live contract, ignoring terminated siblings" do
        create(:contract, :terminated, organization:, external_id: "reused", started_at: 2.months.ago)
        live = create(:contract, :pending, organization:, external_id: "reused")

        expect(organization.contracts.live_by_external_id("reused")).to eq(live)
      end

      it "returns nil when only historical contracts share the id" do
        create(:contract, :terminated, organization:, external_id: "gone")

        expect(organization.contracts.live_by_external_id("gone")).to be_nil
      end
    end
  end
end
