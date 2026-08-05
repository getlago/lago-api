# frozen_string_literal: true

RSpec.describe PaymentProviderCustomers::BaseCustomer do
  subject(:integration_customer) { described_class.new(attributes) }

  let(:attributes) { {} }

  it { is_expected.to belong_to(:organization) }

  describe "validations" do
    subject { create(:stripe_customer, code: "stripe_eu") }

    it { is_expected.to validate_uniqueness_of(:code).scoped_to(:customer_id).allow_nil }

    context "when a provider-backed row uses the reserved manual code" do
      subject { build(:stripe_customer, payment_provider: create(:stripe_provider), code: "manual") }

      it "is invalid" do
        expect(subject).not_to be_valid
        expect(subject.errors.where(:code, :reserved)).to be_present
      end
    end

    context "when the null-provider manual row uses the reserved manual code" do
      subject { build(:manual_payment_provider_customer) }

      it { is_expected.to be_valid }
    end
  end

  describe ".by_code" do
    subject { described_class.by_code("stripe_eu") }

    let!(:matching) { create(:stripe_customer, code: "stripe_eu") }

    before { create(:gocardless_customer, code: "gc_main") }

    it { is_expected.to eq([matching]) }
  end

  describe "#manual?" do
    subject { payment_provider_customer.manual? }

    context "when the row has no payment provider and the reserved manual code" do
      let(:payment_provider_customer) { build(:stripe_customer, payment_provider: nil, code: "manual") }

      it { is_expected.to be(true) }
    end

    context "when the row is backed by a payment provider" do
      let(:payment_provider_customer) do
        build(:stripe_customer, payment_provider: create(:stripe_provider), code: "manual")
      end

      it { is_expected.to be(false) }
    end

    context "when the row has no provider but a different code" do
      let(:payment_provider_customer) { build(:stripe_customer, payment_provider: nil, code: "stripe_eu") }

      it { is_expected.to be(false) }
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
