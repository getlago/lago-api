# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::ApproveService do
  subject(:approve_service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }
  let(:quote_version) do
    create(
      :quote_version,
      :with_subscription_creation_billing_items,
      quote:,
      organization:,
      plan_start_date: "2026-01-01",
      plan_end_date: "2027-01-01"
    )
  end

  describe ".call" do
    let(:result) { approve_service.call }

    context "when the quote version is approvable", :premium do
      it "approves the quote version" do
        freeze_time do
          expect(result).to be_success
          expect(result.quote_version.approved?).to eq(true)
          expect(result.quote_version.approved_at).to eq(Time.current)
        end
      end

      it "creates an order form for the approved quote version" do
        expect { result }.to change(OrderForm, :count).by(1)

        expect(result.order_form).to have_attributes(
          quote_version_id: quote_version.id,
          customer_id: quote.customer_id,
          status: "generated"
        )
      end

      it "enqueues a quote.approved webhook" do
        expect { approve_service.call }
          .to have_enqueued_job_after_commit(SendWebhookJob)
          .with("quote.approved", quote_version)
      end

      it "enqueues an order_form.created webhook" do
        expect { approve_service.call }
          .to have_enqueued_job_after_commit(SendWebhookJob)
          .with("order_form.created", OrderForm)
      end

      it "produces a quote.approved activity log" do
        approve_service.call

        expect(Utils::ActivityLog).to have_produced("quote.approved").after_commit.with(quote_version)
      end

      it "produces an order_form.created activity log" do
        result = approve_service.call

        expect(Utils::ActivityLog).to have_produced("order_form.created").after_commit.with(result.order_form)
      end

      it "persists the raw computed mention variables snapshot" do
        expect(result).to be_success
        expect(result.quote_version.reload.mention_variables).to include(
          "customer_name" => quote.customer.display_name,
          "quote_number" => quote.number,
          "commercial_terms_start_date" => "2026-01-01",
          "commercial_terms_term_duration" => {"unit" => "years", "count" => 1}
        )
      end
    end

    context "with concurrent mutations", :premium do
      it "wraps the work in a per-quote lock" do
        allow(Quotes::LockService).to receive(:call).and_call_original

        result

        expect(Quotes::LockService).to have_received(:call).with(quote: quote_version.quote).at_least(:once)
      end

      it "re-checks the status under the lock and refuses a stale approval" do
        quote_version
        QuoteVersion.find(quote_version.id).update!(status: :voided, void_reason: :manual, voided_at: Time.current)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_approvable"]})
      end
    end

    context "when an expires_at in the future is provided", :premium do
      subject(:approve_service) { described_class.new(quote_version:, expires_at:) }

      let(:expires_at) { 1.month.from_now }

      it "sets expires_at on the created order form" do
        expect(result).to be_success
        expect(result.order_form.expires_at).to be_within(1.second).of(expires_at)
      end
    end

    context "when an expires_at in the past is provided", :premium do
      subject(:approve_service) { described_class.new(quote_version:, expires_at:) }

      let(:expires_at) { 1.day.ago }

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(expires_at: ["invalid_date"])

        quote_version.reload
        expect(quote_version.approved?).to eq(false)
        expect(quote_version.approved_at).to eq(nil)
      end

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end
    end

    context "when the expires_at lands on the deal expiration", :premium do
      subject(:approve_service) { described_class.new(quote_version:, expires_at:) }

      # The quoted plan ends on 2027-01-01 and the signing window has to close strictly before the
      # deal expires, so the boundary day itself is refused.
      let(:expires_at) { Time.utc(2027, 1, 1).end_of_day }

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(expires_at: ["after_deal_expiration"])

        quote_version.reload
        expect(quote_version.approved?).to eq(false)
        expect(quote_version.approved_at).to eq(nil)
      end

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end
    end

    context "when the order form creation fails with a non-validation failure", :premium do
      before do
        allow(OrderForms::CreateService).to receive(:call!)
          .and_raise(BaseService::ForbiddenFailure.new(BaseResult.new, code: "feature_unavailable"))
      end

      it "surfaces the failure instead of letting it escape" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end

      it "rolls the approval back" do
        result

        quote_version.reload
        expect(quote_version.draft?).to eq(true)
        expect(quote_version.approved_at).to eq(nil)
      end
    end

    context "when the quote lock cannot be acquired", :premium do
      before do
        allow(Quotes::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "returns a concurrency conflict instead of raising" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(base: ["concurrency_conflict"])
      end
    end

    context "when the billing items are incomplete", :premium do
      let(:quote_version) do
        create(:quote_version, quote:, organization:)
      end

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({"billing_items.plans": ["value_is_mandatory"]})

        expect(quote_version.reload.approved?).to eq(false)
      end

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end
    end

    context "when the quote is one_off", :premium do
      let(:quote) { create(:quote, organization:, order_type: :one_off) }
      let(:quote_version) do
        create(
          :quote_version,
          :with_one_off_billing_items,
          quote:,
          organization:
        )
      end

      it "approves the quote version" do
        expect(result).to be_success
        expect(result.quote_version.approved?).to eq(true)
      end

      context "when the billing items are incomplete" do
        let(:quote_version) { create(:quote_version, quote:, organization:) }

        it "does not approve the quote version" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({"billing_items.addOns": ["value_is_mandatory"]})

          expect(quote_version.reload.approved?).to eq(false)
        end

        it "does not create an order form" do
          expect { result }.not_to change(OrderForm, :count)
        end
      end
    end

    context "when the quote version is voided", :premium do
      let(:quote_version) { create(:quote_version, :voided, quote:, organization:) }

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_approvable"]})

        quote_version.reload
        expect(quote_version.approved?).to eq(false)
        expect(quote_version.approved_at).to eq(nil)
      end

      it "does not create an order form" do
        expect { result }.not_to change(OrderForm, :count)
      end
    end

    context "when the quote version is already approved", :premium do
      let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_approvable"]})
      end
    end

    context "when quote version does not exist", :premium do
      let(:quote_version) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("quote_version_not_found")
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end
  end
end
