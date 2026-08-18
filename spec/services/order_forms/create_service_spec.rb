# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::CreateService do
  subject(:create_service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }
  let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }

  describe ".call" do
    let(:result) { create_service.call }

    context "when the quote version is approved", :premium do
      it "creates an order form" do
        expect { result }.to change(OrderForm, :count).by(1)
      end

      it "returns the order form with the expected attributes" do
        expect(result).to be_success
        expect(result.order_form).to have_attributes(
          organization_id: organization.id,
          customer_id: quote.customer_id,
          quote_version_id: quote_version.id,
          status: "generated",
          expires_at: nil
        )
      end

      it "enqueues an order_form.created webhook" do
        expect { create_service.call }
          .to have_enqueued_job_after_commit(SendWebhookJob)
          .with("order_form.created", OrderForm)
      end

      it "produces an order_form.created activity log" do
        result = create_service.call

        expect(Utils::ActivityLog).to have_produced("order_form.created").after_commit.with(result.order_form)
      end
    end

    context "when an expires_at in the future is provided", :premium do
      subject(:create_service) { described_class.new(quote_version:, expires_at:) }

      let(:expires_at) { 1.month.from_now }

      it "sets expires_at on the order form" do
        expect(result).to be_success
        expect(result.order_form.expires_at).to be_within(1.second).of(expires_at)
      end
    end

    context "when an expires_at in the past is provided", :premium do
      subject(:create_service) { described_class.new(quote_version:, expires_at:) }

      let(:expires_at) { 1.day.ago }

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(expires_at: ["invalid_date"])
      end
    end

    context "when an expires_at outliving the deal is provided", :premium do
      subject(:create_service) { described_class.new(quote_version:, expires_at:) }

      let(:quote_version) do
        create(
          :quote_version,
          :approved,
          :with_subscription_creation_billing_items,
          quote:,
          organization:,
          plan_end_date: 1.month.from_now.to_date.iso8601
        )
      end
      let(:expires_at) { 2.months.from_now }

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(expires_at: ["after_deal_expiration"])
      end
    end

    context "when an expires_at falls on the day the deal ends", :premium do
      subject(:create_service) { described_class.new(quote_version:, expires_at:) }

      let(:end_date) { 1.month.from_now.to_date }
      let(:quote_version) do
        create(
          :quote_version,
          :approved,
          :with_subscription_creation_billing_items,
          quote:,
          organization:,
          plan_end_date: end_date.iso8601
        )
      end
      let(:expires_at) { end_date.to_time }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(expires_at: ["after_deal_expiration"])
      end
    end

    context "when an expires_at inside the deal is provided", :premium do
      subject(:create_service) { described_class.new(quote_version:, expires_at:) }

      let(:quote_version) do
        create(
          :quote_version,
          :approved,
          :with_subscription_creation_billing_items,
          quote:,
          organization:,
          plan_end_date: 2.months.from_now.to_date.iso8601
        )
      end
      let(:expires_at) { 1.month.from_now }

      it "creates an order form" do
        expect(result).to be_success
        expect(result.order_form.expires_at).to be_within(1.second).of(expires_at)
      end
    end

    # A one_off deal carries no date the execution flow can outlive.
    context "when the deal is one_off", :premium do
      subject(:create_service) { described_class.new(quote_version:, expires_at:) }

      let(:quote_version) do
        create(:quote_version, :approved, :with_one_off_billing_items, quote:, organization:)
      end
      let(:expires_at) { 10.years.from_now }

      it "creates an order form" do
        expect(result).to be_success
      end
    end

    context "when the quote version is not approved", :premium do
      let(:quote_version) { create(:quote_version, quote:, organization:) }

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({quote_version: ["not_approved"]})
      end
    end

    context "when license is not premium" do
      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end

      it "returns a forbidden failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    context "when an order form already exists for the quote version", :premium do
      before { create(:order_form, quote_version:, organization:, customer: quote.customer) }

      it "does not create another order form" do
        expect { result }.not_to change(OrderForm, :count)
      end

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(quote_version_id: ["value_already_exist"])
      end
    end

    context "when the quote version does not exist", :premium do
      let(:quote_version) { nil }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("quote_version_not_found")
      end
    end
  end
end
