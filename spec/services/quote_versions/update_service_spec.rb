# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::UpdateService do
  subject(:update_service) { described_class.new(quote_version:, params: update_params) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }
  let(:quote_version) { create(:quote_version, quote:, organization:) }
  let(:update_params) {
    {
      billing_items: {},
      content: "Test content",
      currency: "USD"
    }
  }

  describe ".call" do
    let(:result) { update_service.call }

    context "when draft quote version", :premium do
      it "updates the quote version" do
        expect(result).to be_success
        expect(result.quote_version.id).to eq(quote_version.id)
        expect(result.quote_version.quote_id).to eq(quote_version.quote_id)
        expect(result.quote_version.organization_id).to eq(quote_version.organization_id)
        expect(result.quote_version.version).to eq(quote_version.version)
        expect(result.quote_version.draft?).to eq(true)
        expect(result.quote_version.billing_items).to eq({})
        expect(result.quote_version.content).to eq("Test content")
        expect(result.quote_version.currency).to eq("USD")
      end

      # Called through the class so the request goes through the activity log middleware, which an
      # instance #call bypasses.
      it "produces a quote.updated activity log" do
        described_class.call(quote_version:, params: update_params)

        expect(Utils::ActivityLog).to have_produced("quote.updated").after_commit.with(quote_version)
      end
    end

    context "when the quote is one_off", :premium do
      let(:quote) { create(:quote, organization:, order_type: :one_off) }
      let(:add_on) { create(:add_on, organization:) }
      let(:update_params) { {billing_items:, currency: "EUR"} }
      let(:billing_items) do
        {
          "addOns" => [
            {
              "id" => add_on.id,
              "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
              "type" => "add_on",
              "payload" => {
                "code" => add_on.code,
                "units" => 2,
                "unitAmountCents" => 10_000,
                "totalAmountCents" => 20_000
              }
            }
          ]
        }
      end

      it "updates the billing items" do
        expect(result).to be_success
        expect(result.quote_version.reload.billing_items).to eq(billing_items)
      end

      context "when the payload is invalid" do
        let(:billing_items) do
          {
            "addOns" => [
              {"id" => "not-a-uuid", "localId" => "3d08b2df", "type" => "add_on", "payload" => {"units" => 0}}
            ]
          }
        end

        it "returns a validation failure and does not persist the changes" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(
            {
              "billing_items.addOns.0.id": ["invalid_format"],
              "billing_items.addOns.0.payload.units": ["invalid_value"]
            }
          )

          expect(quote_version.reload.billing_items).to be_nil
        end
      end

      context "when the currency is invalid" do
        let(:update_params) { {currency: "DOUBLOON"} }

        it "returns a validation failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({currency: ["invalid_currency"]})
        end
      end

      context "when a billing entity is named" do
        let(:billing_entity) { create(:billing_entity, organization:) }
        let(:update_params) { {billing_entity_id: billing_entity.id} }

        it "pins it on the version" do
          expect(result).to be_success
          expect(result.quote_version.billing_entity_id).to eq(billing_entity.id)
        end
      end

      context "when the named billing entity belongs to another organization" do
        let(:billing_entity) { create(:billing_entity) }
        let(:update_params) { {billing_entity_id: billing_entity.id} }

        it "returns a validation failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({billing_entity_id: ["billing_entity_not_found"]})
        end

        it "leaves the version untouched" do
          result

          expect(quote_version.reload.billing_entity_id).to eq(nil)
        end
      end

      context "when the billing entity is cleared" do
        let(:billing_entity) { create(:billing_entity, organization:) }
        let(:quote_version) { create(:quote_version, quote:, organization:, billing_entity:) }
        let(:update_params) { {billing_entity_id: nil} }

        it "lets the deal follow the customer's own entity again" do
          expect(result).to be_success
          expect(result.quote_version.billing_entity_id).to eq(nil)
        end
      end
    end

    context "when the currency changes", :premium do
      let(:plan) { create(:plan, organization:, amount_currency: "EUR") }
      let(:plan_item) do
        {
          "id" => plan.id,
          "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
          "type" => "plan",
          "payload" => {"code" => plan.code, "startDate" => Date.current.iso8601}
        }
      end
      let(:quote_version) do
        create(:quote_version, quote:, organization:, currency: "EUR", billing_items: {"plans" => [plan_item]})
      end
      let(:update_params) { {currency: "USD"} }

      it "reprices the quoted plan in the new currency" do
        expect(result).to be_success
        expect(result.quote_version.billing_items.dig("plans", 0, "overrides", "amountCurrency")).to eq("USD")
      end

      context "when the catalog plan is already priced in the new currency" do
        let(:plan) { create(:plan, organization:, amount_currency: "USD") }

        # An overrides object would make the execution service mint a duplicate override plan for a
        # plan that needs none.
        it "leaves the item without an overrides object" do
          expect(result).to be_success
          expect(result.quote_version.billing_items.dig("plans", 0, "overrides")).to eq(nil)
        end
      end

      context "when a wallet credit states its own currency" do
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {
              "walletCredits" => [
                {"localId" => "d9169d94", "type" => "wallet_credit", "payload" => {"currency" => "EUR", "paidCredits" => "100"}},
                {"localId" => "a1b2c3d4", "type" => "wallet_credit", "payload" => {"paidCredits" => "50"}}
              ]
            }
          )
        end

        it "realigns the stated one and leaves the silent one alone" do
          expect(result).to be_success

          credits = result.quote_version.billing_items["walletCredits"]
          expect(credits.first["payload"]["currency"]).to eq("USD")
          expect(credits.second["payload"]).not_to have_key("currency")
        end
      end

      context "when a fixed-amount coupon is priced in another currency" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "fixed_amount", amount_currency: "EUR") }
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {
              "coupons" => [{"id" => coupon.id, "localId" => "c1", "type" => "coupon", "payload" => {"code" => coupon.code}}]
            }
          )
        end

        # The coupon is applied in its own currency, so it cannot follow the deal.
        it "refuses the change on the currency field" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({currency: ["currencies_does_not_match"]})
        end
      end

      context "when the quote amends a running subscription" do
        let(:subscription) { create(:subscription, organization:, customer: quote.customer) }
        let(:quote) do
          create(:quote, organization:, subscription: create(:subscription, organization:), order_type: :subscription_amendment)
        end

        # Repricing would switch a running subscription mid-life, leaving its invoices behind in the
        # currency it started in.
        it "refuses the change" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq({currency: ["not_supported_for_order_type"]})
        end
      end
    end

    context "when approved quote version", :premium do
      let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_editable"]})
      end
    end

    context "when voided quote version", :premium do
      let(:quote_version) { create(:quote_version, :voided, quote:, organization:) }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_editable"]})
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
