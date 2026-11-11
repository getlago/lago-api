# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperation do
  subject(:operation) { build(:billing_operation, organization:, customer:, contract_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { contract_customer }
  let(:contract_customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization: card_organization, customer: contract_customer) }
  let(:card_organization) { organization }
  let(:contract_rate_card) { create(:contract_rate_card, organization: card_organization, contract:) }

  describe "enums" do
    it do
      expect(operation).to define_enum_for(:causation_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(described_class::CAUSATION_TYPES)
      expect(operation).to define_enum_for(:cancelled_causation_type)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(described_class::CANCELLED_CAUSATION_TYPES)
        .with_prefix
    end
  end

  describe "associations" do
    it do
      expect(operation).to belong_to(:organization)
      expect(operation).to belong_to(:customer)
      expect(operation).to belong_to(:contract_rate_card)
      expect(operation).to belong_to(:invoice).optional
    end
  end

  describe "Scopes" do
    describe ".pending" do
      let(:pending_operation) { create(:billing_operation) }
      let(:cancelled_operation) do
        create(
          :billing_operation,
          cancelled_at: Time.current,
          cancelled_causation_type: :contract_termination
        )
      end

      before do
        pending_operation
        create(:billing_operation, processed_at: Time.current)
        cancelled_operation
      end

      it "excludes processed and cancelled operations" do
        expect(described_class.pending).to eq([pending_operation])
      end

      it "persists cancellation without marking the operation processed" do
        expect(cancelled_operation.reload.cancelled_causation_type).to eq("contract_termination")
        expect(cancelled_operation.processed_at).to be_nil
      end
    end
  end

  describe "validations" do
    it do
      expect(operation).to validate_inclusion_of(:action_type).in_array(described_class::ACTION_TYPES.values)
      expect(operation).to validate_presence_of(:billing_at)
      expect(operation).to validate_presence_of(:target_cycle_started_at)
    end

    describe "identity validation" do
      before { operation.valid? }

      it "accepts a customer and rate card from the same organization" do
        expect(operation.errors).to be_empty
      end

      context "when the customer differs from the contract customer" do
        let(:customer) { create(:customer, organization:) }

        it { expect(operation.errors.where(:customer, :invalid)).to be_present }
      end

      context "when the rate card belongs to another organization" do
        let(:card_organization) { create(:organization) }
        let(:contract_customer) { create(:customer, organization: card_organization) }

        it { expect(operation.errors.where(:organization, :invalid)).to be_present }
      end

      context "when the customer belongs to another organization" do
        let(:other_organization) { create(:organization) }
        let(:customer) { create(:customer, organization: other_organization) }

        it { expect(operation.errors.where(:organization, :invalid)).to be_present }
      end

      context "without a customer" do
        let(:customer) { nil }

        it { expect(operation.errors.where(:customer, :blank)).to be_present }
      end

      context "without a rate card" do
        let(:contract_rate_card) { nil }

        it { expect(operation.errors.where(:contract_rate_card, :blank)).to be_present }
      end

      context "without an organization" do
        let(:organization) { nil }
        let(:customer) { nil }
        let(:contract_customer) { nil }
        let(:contract_rate_card) { nil }

        it { expect(operation.errors.where(:organization, :blank)).to be_present }
      end
    end
  end
end
