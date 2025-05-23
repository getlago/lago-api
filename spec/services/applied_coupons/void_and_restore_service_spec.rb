# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupons::VoidAndRestoreService, type: :service do
  subject(:void_and_restore_service) { described_class.new(credit:) }

  let(:credit) { build(:credit, applied_coupon: )}
  let(:applied_coupon) { build(:applied_coupon, status: :active) }

  describe "#call" do

    context "when applied coupon does not exist" do
      let(:applied_coupon) { nil }

      it "returns not_found_failure" do
        result = void_and_restore_service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("applied_coupon")
      end
    end

    context "when applied coupon is already voided" do
      before { applied_coupon.mark_as_voided! }

      it "returns not_allowed_failure" do
        result = void_and_restore_service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("already_voided")
      end
    end

    context "when applied coupon has unlimited usage" do

      let(:applied_coupon) do
        create(:applied_coupon, frequency: :forever)
      end

      it "returns early without voiding or creating a new coupon" do
        result = void_and_restore_service.call

        expect(result).to be_success
        expect(applied_coupon.reload).not_to be_voided
        expect(result.restored_applied_coupon).to be_nil
      end
    end

    context "when applied coupon exists and is not voided" do
      let(:customer) { create(:customer) }
      let(:applied_coupon) do
        create(:applied_coupon,
               coupon: coupon,
               status: coupon.status,
               amount_currency: coupon.amount_currency,
               customer: customer,
               amount_cents: coupon.amount_cents,
               percentage_rate: coupon.percentage_rate,
               frequency: coupon.frequency
        )
      end


      context "when applied coupon type is frequency once and is fixed amount" do
        let(:coupon) do
          create(:coupon,
                 coupon_type: "fixed_amount",
                 status: "active",
                 expiration_at: nil,
                 amount_cents: 460,
                 amount_currency: "EUR",
                 frequency: "once",
                 description: "Coupon Description"
          )
        end

        it "voids the applied coupon and creates a new one" do
          result = void_and_restore_service.call

          expect(result).to be_success
          expect(applied_coupon.reload).to be_voided
          expect(result.restored_applied_coupon).to be_present
          expect(result.restored_applied_coupon).not_to eq(applied_coupon)
          expect(result.restored_applied_coupon.coupon).to eq(coupon)
          expect(result.restored_applied_coupon.customer).to eq(customer)
          expect(result.restored_applied_coupon.amount_cents).to eq(applied_coupon.amount_cents)
          expect(result.restored_applied_coupon.amount_currency).to eq(applied_coupon.amount_currency)
          expect(result.restored_applied_coupon.percentage_rate).to eq(applied_coupon.percentage_rate)
          expect(result.restored_applied_coupon.frequency).to eq(applied_coupon.frequency)
          expect(result.restored_applied_coupon.frequency_duration).to eq(applied_coupon.frequency_duration)
        end
      end

      context "when applied coupon is percentage and once" do
        let(:coupon) do
          create(:coupon,
                 coupon_type: :percentage,
                 status: "active",
                 expiration_at: nil,
                 percentage_rate: 25.0,
                 frequency: :once
          )
        end

        it "voids and restores a percentage once coupon" do
          result = void_and_restore_service.call

          expect(result).to be_success
          expect(applied_coupon.reload).to be_voided
          expect(result.restored_applied_coupon).to be_present
          expect(result.restored_applied_coupon.percentage_rate).to eq(coupon.percentage_rate)
        end
      end

      context "when applied coupon is fixed amount and recurring" do
        let(:coupon) do
          create(:coupon,
                 coupon_type: :fixed_amount,
                 status: "active",
                 expiration_at: nil,
                 amount_cents: 1000,
                 amount_currency: "EUR",
                 frequency: :recurring,
                 frequency_duration: 6)
        end

        let(:applied_coupon) do
          create(:applied_coupon,
                 coupon: coupon,
                 customer: customer,
                 status: :active,
                 frequency: :recurring,
                 frequency_duration: 6,
                 frequency_duration_remaining: 4)
        end

        it "restores usage by incrementing frequency_duration_remaining and returns the same applied_coupon" do
          expect {
            result = void_and_restore_service.call

            expect(result).to be_success
            expect(result.restored_applied_coupon).to eq(applied_coupon)
          }.to change {
            applied_coupon.reload.frequency_duration_remaining
          }.from(4).to(5)
        end
      end
    end
  end
end
