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

      context "when an invoice is assigned" do
        let(:invoice) { create(:invoice, organization:, customer:) }
        let(:operation) { build(:billing_operation, organization:, customer:, contract_rate_card:, invoice:) }

        it "accepts an invoice for the same organization and customer" do
          expect(operation).to be_valid
        end

        context "when the invoice belongs to another customer in the same organization" do
          let(:other_customer) { create(:customer, organization:) }
          let(:invoice) { create(:invoice, organization:, customer: other_customer) }

          it do
            expect(operation).not_to be_valid
            expect(operation.errors.where(:invoice, :invalid)).to be_present
          end
        end

        context "when the invoice belongs to another organization" do
          let(:other_organization) { create(:organization) }
          let(:other_customer) { create(:customer, organization: other_organization) }
          let(:invoice) { create(:invoice, organization: other_organization, customer: other_customer) }

          it do
            expect(operation).not_to be_valid
            expect(operation.errors.where(:invoice, :invalid)).to be_present
          end
        end
      end

      context "when an assigned association id does not exist" do
        let(:missing_id) { SecureRandom.uuid }

        context "with a missing customer" do
          let(:customer) { nil }
          let(:operation) { build(:billing_operation, organization:, customer_id: missing_id, contract_rate_card:) }

          it do
            expect(operation).not_to be_valid
            expect(operation.errors.where(:customer, :invalid)).to be_present
          end
        end

        context "with a missing rate card" do
          let(:operation) { build(:billing_operation, organization:, customer:, contract_rate_card_id: missing_id) }

          it do
            expect(operation).not_to be_valid
            expect(operation.errors.where(:contract_rate_card, :invalid)).to be_present
          end
        end

        context "with a missing invoice" do
          let(:operation) { build(:billing_operation, organization:, customer:, contract_rate_card:, invoice_id: missing_id) }

          it do
            expect(operation).not_to be_valid
            expect(operation.errors.where(:invoice, :invalid)).to be_present
          end
        end
      end

      context "when an unsaved invoice is assigned" do
        let(:invoice) { build(:invoice, organization:, customer: other_customer) }
        let(:other_customer) { create(:customer, organization:) }
        let(:operation) { build(:billing_operation, organization:, customer:, contract_rate_card:, invoice:) }

        it { expect(operation.errors.where(:invoice, :invalid)).to be_present }
      end

      context "when reassigning identity associations" do
        let(:persisted_operation) { create(:billing_operation, organization:, customer:, contract_rate_card:).reload }
        let(:other_organization) { create(:organization) }
        let(:other_customer) { create(:customer, organization: other_organization) }
        let(:other_contract) { create(:contract, organization: other_organization, customer: other_customer) }
        let(:other_rate_card) { create(:contract_rate_card, organization: other_organization, contract: other_contract) }
        let(:other_invoice) { create(:invoice, organization: other_organization, customer: other_customer) }
        let(:unsaved_invoice) { build(:invoice, organization: other_organization, customer: other_customer) }

        it "revalidates when the invoice changes" do
          expect(persisted_operation.update(invoice: other_invoice)).to be(false)
          expect(persisted_operation.errors.where(:invoice, :invalid)).to be_present
        end

        it "validates an unsaved invoice before linking it" do
          expect(persisted_operation.update(invoice: unsaved_invoice)).to be(false)
          expect(persisted_operation.errors.where(:invoice, :invalid)).to be_present
        end

        it "revalidates when the organization changes" do
          expect(persisted_operation.update(organization: other_organization)).to be(false)
          expect(persisted_operation.errors.where(:organization, :invalid)).to be_present
        end

        it "revalidates when the customer changes" do
          expect(persisted_operation.update(customer: other_customer)).to be(false)
          expect(persisted_operation.errors.where(:organization, :invalid)).to be_present
        end

        it "revalidates when the rate card changes" do
          expect(persisted_operation.update(contract_rate_card: other_rate_card)).to be(false)
          expect(persisted_operation.errors.where(:organization, :invalid)).to be_present
        end
      end

      context "when updating state without changing identity" do
        let(:persisted_operation) { create(:billing_operation).reload }
        let(:queries) { [] }

        it "does not load identity associations" do
          persisted_operation

          ActiveSupport::Notifications.subscribed(
            ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:name] != "SCHEMA" },
            "sql.active_record"
          ) do
            persisted_operation.update!(processed_at: Time.current)
          end

          expect(queries.grep(/SELECT.*(organizations|customers|contract_rate_cards|contracts|invoices)/i)).to be_empty
        end
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

    describe "cancellation state validation" do
      context "with a pending operation" do
        it { expect(operation).to be_valid }
      end

      context "with a completed operation" do
        let(:operation) { build(:billing_operation, processed_at: Time.current) }

        it { expect(operation).to be_valid }
      end

      context "with a cancelled operation" do
        let(:operation) { build(:billing_operation, cancelled_at: Time.current, cancelled_causation_type: :contract_termination) }

        it { expect(operation).to be_valid }
      end

      context "with a cancellation time but no cause" do
        let(:operation) { build(:billing_operation, cancelled_at: Time.current) }

        it do
          expect(operation).not_to be_valid
          expect(operation.errors.where(:cancelled_at, :invalid)).to be_present
        end
      end

      context "with a cause but no cancellation time" do
        let(:operation) { build(:billing_operation, cancelled_causation_type: :contract_termination) }

        it do
          expect(operation).not_to be_valid
          expect(operation.errors.where(:cancelled_at, :invalid)).to be_present
        end
      end

      context "with a cancelled and processed operation" do
        let(:operation) do
          build(:billing_operation, cancelled_at: Time.current, cancelled_causation_type: :contract_termination, processed_at: Time.current)
        end

        it do
          expect(operation).not_to be_valid
          expect(operation.errors.where(:processed_at, :invalid)).to be_present
        end
      end
    end
  end

  describe "#due_for_processing?" do
    subject(:due_for_processing) { operation.due_for_processing?(timestamp:) }

    let(:timestamp) { Time.utc(2026, 2, 1) }
    let(:billing_at) { timestamp }
    let(:processed_at) { nil }
    let(:cancelled_at) { nil }
    let(:operation) { described_class.new(billing_at:, processed_at:, cancelled_at:) }

    context "when billing is in the past" do
      let(:billing_at) { timestamp - 1.second }

      it { is_expected.to be(true) }
    end

    context "when billing is exactly due" do
      it { is_expected.to be(true) }
    end

    context "when billing is in the future" do
      let(:billing_at) { timestamp + 1.second }

      it { is_expected.to be(false) }
    end

    context "when already processed" do
      let(:processed_at) { timestamp }

      it { is_expected.to be(false) }
    end

    context "when cancelled" do
      let(:cancelled_at) { timestamp }

      it { is_expected.to be(false) }
    end
  end
end
