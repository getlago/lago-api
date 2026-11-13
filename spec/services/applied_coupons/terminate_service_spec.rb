# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupons::TerminateService do
  subject(:terminate_service) { described_class.new(applied_coupon:) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create(:membership) }
  let(:coupon) { create(:coupon, status: "active", organization:) }
  let(:applied_coupon) { create(:applied_coupon, coupon:) }

  describe "#call" do
    it "terminates the applied coupon" do
      result = terminate_service.call

      expect(result).to be_success
      expect(result.applied_coupon).to be_terminated
    end

    it "produces an activity log" do
      described_class.call(applied_coupon:)

      expect(Utils::ActivityLog).to have_produced("applied_coupon.deleted").with(applied_coupon)
    end

    context "when the customer is deleted and activity logs are available" do
      subject(:result) { described_class.call(applied_coupon: AppliedCoupon.find(applied_coupon.id)) }

      let(:customer) { create(:customer, organization:) }
      let(:applied_coupon) { create(:applied_coupon, coupon:, customer:) }

      before do
        applied_coupon
        customer.discard!
        allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      end

      it "terminates the applied coupon" do
        expect(result).to be_success
        expect(result.applied_coupon.customer).to eq(customer)
        expect(applied_coupon.reload).to be_terminated
      end
    end

    context "when applied coupon is already terminated" do
      before { applied_coupon.mark_as_terminated! }

      it "does not impact the applied coupon" do
        terminated_at = applied_coupon.reload.terminated_at
        result = terminate_service.call

        expect(result).to be_success
        expect(result.applied_coupon).to be_terminated
        expect(result.applied_coupon.terminated_at).to eq(terminated_at)
      end
    end
  end
end
