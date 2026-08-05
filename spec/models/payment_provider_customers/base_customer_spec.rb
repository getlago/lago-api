# frozen_string_literal: true

RSpec.describe PaymentProviderCustomers::BaseCustomer do
  subject(:integration_customer) { described_class.new(attributes) }

  let(:attributes) { {} }

  it { is_expected.to belong_to(:organization) }

  describe "validations" do
    subject { create(:stripe_customer, code: "stripe_eu") }

    it { is_expected.to validate_uniqueness_of(:code).scoped_to(:customer_id).allow_nil }

    describe "code_is_not_reserved" do
      it "rejects a provider-backed connection using the reserved manual code" do
        customer = create(:customer)
        provider = create(:stripe_provider, organization: customer.organization)
        connection = create(:stripe_customer, customer:, organization: customer.organization, payment_provider: provider)
        connection.code = "lago_manual"

        expect(connection).not_to be_valid
        expect(connection.errors[:code]).to include("value_is_reserved")
      end

      it "allows a null-provider row to use the manual code" do
        customer = create(:customer)
        manual = described_class.new(
          customer:,
          organization: customer.organization,
          type: "PaymentProviderCustomers::BaseCustomer",
          code: "lago_manual"
        )

        expect(manual).to be_valid
      end
    end
  end

  describe "scopes" do
    describe ".by_code" do
      it "returns connections matching the code" do
        organization = create(:organization)
        matching = create(:stripe_customer, customer: create(:customer, organization:), code: "stripe_eu")
        create(:stripe_customer, customer: create(:customer, organization:), code: "other")

        expect(described_class.by_code("stripe_eu")).to eq([matching])
      end
    end
  end

  describe "#manual?" do
    it "is true for a null-provider row coded manual" do
      expect(described_class.new(payment_provider_id: nil, code: "lago_manual").manual?).to be(true)
    end

    it "is false for a provider-backed connection coded manual" do
      expect(described_class.new(payment_provider_id: SecureRandom.uuid, code: "lago_manual").manual?).to be(false)
    end

    it "is false for a null-provider row with a different code" do
      expect(described_class.new(payment_provider_id: nil, code: "other").manual?).to be(false)
    end
  end

  describe "#legacy_provider_method_id" do
    subject { customer.legacy_provider_method_id }

    context "when payment_method_id is set in settings" do
      let(:customer) { build(:stripe_customer, settings: {"payment_method_id" => "pm_123"}) }

      it { is_expected.to eq("pm_123") }
    end

    context "when only provider_mandate_id is set in settings" do
      let(:customer) { build(:gocardless_customer, settings: {"provider_mandate_id" => "mandate_123"}) }

      it { is_expected.to eq("mandate_123") }
    end

    context "when neither is set" do
      let(:customer) { build(:stripe_customer, settings: {}) }

      it { is_expected.to be_nil }
    end
  end
end
