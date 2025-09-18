# frozen_string_literal: true

require "rails_helper"

RSpec.describe Coupon do
  subject(:coupon) { build(:coupon) }

  it_behaves_like "paper_trail traceable"

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0).allow_nil }

  specify do
    expect(subject)
      .to validate_inclusion_of(:amount_currency)
      .in_array(described_class.currency_list)
  end

  describe "validations" do
    describe "of amount cents" do
      subject { coupon }

      let(:coupon) { build_stubbed(:coupon, coupon_type:) }

      context "when coupon type is fixed amount" do
        let(:coupon_type) { :fixed_amount }

        it { is_expected.to validate_presence_of(:amount_cents) }
      end

      context "when coupon type is percentage" do
        let(:coupon_type) { :percentage }

        it { is_expected.not_to validate_presence_of(:amount_cents) }
      end
    end

    describe "of amount currency" do
      subject { coupon }

      let(:coupon) { build_stubbed(:coupon, coupon_type:) }

      context "when coupon type is fixed amount" do
        let(:coupon_type) { :fixed_amount }

        it { is_expected.to validate_presence_of(:amount_currency) }
      end

      context "when coupon type is percentage" do
        let(:coupon_type) { :percentage }

        it { is_expected.not_to validate_presence_of(:amount_currency) }
      end
    end

    describe "of percentage rate" do
      subject { coupon }

      let(:coupon) { build_stubbed(:coupon, coupon_type:) }

      context "when coupon type is fixed amount" do
        let(:coupon_type) { :fixed_amount }

        it { is_expected.not_to validate_presence_of(:percentage_rate) }
      end

      context "when coupon type is percentage" do
        let(:coupon_type) { :percentage }

        it { is_expected.to validate_presence_of(:percentage_rate) }
      end
    end
  end

  describe ".mark_as_terminated" do
    it "terminates the coupon" do
      coupon.mark_as_terminated!

      aggregate_failures do
        expect(coupon).to be_terminated
        expect(coupon.terminated_at).to be_present
      end
    end
  end
end
