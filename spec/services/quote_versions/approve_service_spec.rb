# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::ApproveService do
  subject(:approve_service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }
  let(:quote_version) do
    create(:quote_version, quote:, organization:, start_date: Date.new(2026, 1, 1), end_date: Date.new(2027, 1, 1))
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

      it "persists the raw computed mention variables snapshot" do
        expect(result).to be_success
        expect(result.quote_version.reload.mention_variables).to include(
          "customer_name" => quote.customer.display_name,
          "quote_number" => quote.number,
          "commercial_terms_start_date" => "2026-01-01",
          "commercial_terms_term_duration" => {"unit" => "years", "count" => 1}
        )
      end

      it "does not snapshot billing items for a non one-off quote" do
        allow(QuoteVersions::Snapshots::OneOffService).to receive(:call!).and_call_original

        result

        expect(QuoteVersions::Snapshots::OneOffService).not_to have_received(:call!)
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

    context "when the quote is one_off", :premium do
      let(:quote) { create(:quote, organization:, order_type: :one_off) }
      let(:add_on) { create(:add_on, organization:, amount_cents: 4_200) }
      let(:quote_version) do
        create(
          :quote_version,
          :with_one_off_billing_items,
          quote:,
          organization:,
          add_on:,
          start_date: Date.new(2026, 1, 1),
          end_date: Date.new(2027, 1, 1)
        )
      end

      it "approves the quote version" do
        expect(result).to be_success
        expect(result.quote_version.approved?).to eq(true)
      end

      it "computes the billing items snapshot" do
        allow(QuoteVersions::Snapshots::OneOffService).to receive(:call!).and_call_original

        result

        expect(QuoteVersions::Snapshots::OneOffService).to have_received(:call!).with(quote_version:)
      end

      it "freezes the add-on catalog data into billing_items" do
        expect(result).to be_success

        payload = result.quote_version.reload.billing_items["addons"].first["payload"]
        expect(payload).to include("code" => add_on.code, "name" => add_on.name, "unit_amount_cents" => 4_200)
      end

      it "keeps the snapshot frozen when the add-on changes after approval" do
        expect(result).to be_success
        frozen_payload = quote_version.reload.billing_items["addons"].first["payload"]

        add_on.update!(name: "Renamed", amount_cents: 9_999)

        expect(quote_version.reload.billing_items["addons"].first["payload"]).to eq(frozen_payload)
      end

      it "keeps the snapshot after the add-on is discarded" do
        expect(result).to be_success

        add_on.discard

        payload = quote_version.reload.billing_items["addons"].first["payload"]
        expect(payload["unit_amount_cents"]).to eq(4_200)
      end

      context "when quote-level dates are absent" do
        let(:quote_version) { create(:quote_version, :with_one_off_billing_items, quote:, organization:, add_on:) }

        it "approves and leaves commercial term mention variables blank" do
          expect(result).to be_success
          expect(result.quote_version.approved?).to eq(true)
          expect(result.order_form).to be_present
          expect(result.quote_version.mention_variables["commercial_terms_start_date"]).to be_nil
          expect(result.quote_version.mention_variables["commercial_terms_term_duration"]).to be_nil
        end
      end

      context "when the billing items are incomplete" do
        let(:quote_version) { create(:quote_version, quote:, organization:) }

        it "does not approve the quote version" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({"billing_items.addons": ["value_is_mandatory"]})

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
