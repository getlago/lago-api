# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersion do
  subject(:quote_version) { create(:quote_version) }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .with_values(draft: "draft", approved: "approved", voided: "voided")
        .with_default(:draft)
        .validating(allowing_nil: false)

      expect(subject).to define_enum_for(:void_reason)
        .backed_by_column_of_type(:enum)
        .with_values(
          manual: "manual",
          superseded: "superseded",
          cascade_of_expired: "cascade_of_expired",
          cascade_of_voided: "cascade_of_voided"
        )
        .without_instance_methods
        .validating(allowing_nil: true)
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:quote)
      expect(subject).to belong_to(:billing_entity).optional
      expect(subject).to have_one(:order_form)
    end
  end

  describe "validations" do
    it "is valid by default" do
      expect(build(:quote_version)).to be_valid
    end

    describe "void_reason and voided_at" do
      it "are required when status is voided" do
        quote_version = build(:quote_version, status: :voided, void_reason: nil, voided_at: nil)
        expect(quote_version).not_to be_valid

        quote_version.void_reason = :manual
        quote_version.voided_at = Time.current
        expect(quote_version).to be_valid
      end
    end

    describe "approved_at" do
      it "is required when status is approved" do
        quote_version = build(:quote_version, status: :approved, approved_at: nil)
        expect(quote_version).not_to be_valid
      end

      it "is allowed to be nil when status is draft" do
        quote_version = build(:quote_version, status: :draft, approved_at: nil)
        expect(quote_version).to be_valid
      end
    end

    describe "currency" do
      it "must be an ISO 4217 code when set" do
        expect(build(:quote_version, currency: "EUR")).to be_valid
        expect(build(:quote_version, currency: "DOUBLOON")).not_to be_valid
      end

      it "is allowed to be nil while the deal is not approved yet" do
        expect(build(:quote_version, currency: nil)).to be_valid
      end
    end
  end

  describe "sequencing" do
    it "assigns sequential ids per quote" do
      quote = create(:quote)
      v1 = create(:quote_version, :voided, quote:, organization: quote.organization, sequential_id: nil)
      v2 = create(:quote_version, quote:, organization: quote.organization, sequential_id: nil)
      expect([v1.sequential_id, v2.sequential_id]).to eq([1, 2])
    end
  end

  describe "#version" do
    it "is an alias for sequential_id" do
      quote_version = build(:quote_version, sequential_id: 42)
      expect(quote_version.version).to eq(42)
    end
  end

  describe "#customer" do
    it "delegates to the quote" do
      quote = create(:quote)
      quote_version = create(:quote_version, quote:, organization: quote.organization)

      expect(quote_version.customer).to eq(quote.customer)
    end
  end

  describe "#billing_entity" do
    let(:quote) { create(:quote) }

    it "falls back to the customer's billing entity" do
      quote_version = create(:quote_version, quote:, organization: quote.organization)

      expect(quote_version.billing_entity_id).to eq(nil)
      expect(quote_version.billing_entity).to eq(quote.customer.billing_entity)
    end

    it "returns its own billing entity when the deal names one" do
      billing_entity = create(:billing_entity, organization: quote.organization)
      quote_version = create(:quote_version, quote:, organization: quote.organization, billing_entity:)

      expect(quote_version.billing_entity).to eq(billing_entity)
    end

    # The plan change carries the target's binding over, so the document has to name the same issuer.
    context "when the quote amends a subscription bound to another entity" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:target_entity) { create(:billing_entity, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, billing_entity: target_entity) }
      let(:quote) do
        create(:quote, organization:, customer:, subscription:, order_type: :subscription_amendment)
      end

      it "follows the target rather than the customer's own entity" do
        quote_version = create(:quote_version, quote:, organization:)

        expect(target_entity).not_to eq(customer.billing_entity)
        expect(quote_version.billing_entity).to eq(target_entity)
        expect(quote_version.applicable_billing_entity_id).to eq(target_entity.id)
      end

      # The column is optional and only amendments require it, so another order type can carry a
      # subscription its execution then ignores. The document has to ignore it too.
      %i[subscription_creation one_off].each do |order_type|
        context "when a #{order_type} quote carries one anyway" do
          let(:quote) { create(:quote, organization:, customer:, subscription:, order_type:) }

          it "ignores it and follows the customer's own entity" do
            quote_version = create(:quote_version, quote:, organization:)

            expect(quote_version.billing_entity).to eq(customer.billing_entity)
            expect(quote_version.applicable_billing_entity_id).to eq(customer.billing_entity_id)
          end
        end
      end
    end
  end

  describe "#applicable_billing_entity_id" do
    let(:quote) { create(:quote) }

    it "returns the customer's billing entity id when the deal names none" do
      quote_version = create(:quote_version, quote:, organization: quote.organization)

      expect(quote_version.applicable_billing_entity_id).to eq(quote.customer.billing_entity_id)
    end

    it "returns its own billing entity id when the deal names one" do
      billing_entity = create(:billing_entity, organization: quote.organization)
      quote_version = create(:quote_version, quote:, organization: quote.organization, billing_entity:)

      expect(quote_version.applicable_billing_entity_id).to eq(billing_entity.id)
    end
  end
end
