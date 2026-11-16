# frozen_string_literal: true

require "rails_helper"

RSpec.describe Coupons::DestroyService do
  subject(:destroy_service) { described_class.new(coupon:) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create(:membership) }
  let(:coupon) { create(:coupon, organization:) }
  let(:coupon_plan) { create(:coupon_plan, coupon:) }

  describe "#call" do
    before do
      coupon
    end

    it "soft deletes the coupon" do
      freeze_time do
        expect { destroy_service.call }.to change(Coupon, :count).by(-1)
          .and change { coupon.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "soft deletes all the related coupon_plans" do
      freeze_time do
        expect { destroy_service.call }.to change { coupon_plan.reload.deleted_at }
          .from(nil).to(Time.current)
      end
    end

    it "produces an activity log" do
      described_class.call(coupon:)

      expect(Utils::ActivityLog).to have_produced("coupon.deleted").after_commit.with(coupon)
    end

    it "enqueues a coupon.deleted webhook" do
      result = destroy_service.call

      expect(SendWebhookJob).to have_been_enqueued.with("coupon.deleted", result.coupon)
    end

    context "with applied coupons" do
      it "terminates applied coupons" do
        applied_coupon = create(:applied_coupon, coupon:)
        result = destroy_service.call

        expect(result).to be_success
        expect(applied_coupon.reload).to be_terminated
      end

      context "when an applied coupon belongs to a deleted customer and activity logs are available", :capture_kafka_messages do
        let(:deleted_customer) { create(:customer, organization:) }
        let(:kept_customer) { create(:customer, organization:) }
        let(:deleted_customer_applied_coupon) { create(:applied_coupon, coupon:, customer: deleted_customer) }
        let(:kept_customer_applied_coupon) { create(:applied_coupon, coupon:, customer: kept_customer) }

        let(:applied_coupon_deleted_logs) do
          kafka_messages
            .map { |message| JSON.parse(message[:payload]) }
            .select { |payload| payload["activity_type"] == "applied_coupon.deleted" }
        end

        before do
          deleted_customer_applied_coupon
          kept_customer_applied_coupon
          deleted_customer.discard!
          allow(Utils::ActivityLog).to receive(:available?).and_return(true)
        end

        it "deletes the coupon, terminates every applied coupon and logs the deleted customer" do
          result = described_class.call(coupon:)

          expect(result).to be_success
          expect(coupon.reload).to be_discarded
          expect(deleted_customer_applied_coupon.reload).to be_terminated
          expect(kept_customer_applied_coupon.reload).to be_terminated

          logged_customers = applied_coupon_deleted_logs.to_h do |payload|
            object = payload["activity_object"]
            [object["lago_id"], object.slice("lago_customer_id", "external_customer_id")]
          end
          expect(logged_customers).to eq(
            deleted_customer_applied_coupon.id => {
              "lago_customer_id" => deleted_customer.id,
              "external_customer_id" => deleted_customer.external_id
            },
            kept_customer_applied_coupon.id => {
              "lago_customer_id" => kept_customer.id,
              "external_customer_id" => kept_customer.external_id
            }
          )
        end

        it "sends the coupon.deleted webhook and activity log once" do
          expect { described_class.call(coupon:) }
            .to have_enqueued_job_after_commit(SendWebhookJob).with("coupon.deleted", coupon).exactly(:once)

          coupon_deleted_logs = kafka_messages
            .map { |message| JSON.parse(message[:payload]) }
            .select { |payload| payload["activity_type"] == "coupon.deleted" }
          expect(coupon_deleted_logs.map { |payload| payload["activity_object"]["lago_id"] }).to eq([coupon.id])
        end
      end
    end

    context "when coupon is not found" do
      let(:coupon) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("coupon_not_found")
      end
    end
  end
end
