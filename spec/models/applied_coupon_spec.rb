# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupon, type: :model do
  subject(:applied_coupon) { create(:applied_coupon) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    subject(:applied_coupon) { create(:applied_coupon, coupon: create(:coupon, :deleted)) }

    it { is_expected.to belong_to(:coupon) }
    it { expect(subject.coupon).not_to be_nil }

    it { is_expected.to belong_to(:customer) }
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to have_many(:credits) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(%i[active terminated]) }
    it { is_expected.to define_enum_for(:frequency).with_values(%i[once recurring forever]) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_inclusion_of(:amount_currency).in_array(described_class.currency_list) }
  end

  describe "#remaining_amount" do
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 50) }
    let(:invoice) { create(:invoice) }

    before do
      create(:credit, applied_coupon: applied_coupon, amount_cents: 10, invoice: invoice)
    end

    context "when invoice is not voided" do
      it "returns the amount minus credit" do
        expect(applied_coupon.remaining_amount).to eq(40)
      end
    end

    context "when invoice is voided" do
      let(:invoice) { create(:invoice, status: :voided) }

      it "ignores the credit amount" do
        expect(applied_coupon.remaining_amount).to eq(50)
      end
    end
  end

  describe "#mark_as_terminated!" do
    it "marks the applied coupon as terminated" do
      expect { applied_coupon.mark_as_terminated! }.to change(applied_coupon, :status).to("terminated").and \
        change(applied_coupon, :terminated_at).to be_present
    end
  end
end
