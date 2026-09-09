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

        # An item that never carried the key, on a deal its catalog already matches, is left exactly
        # as it arrived rather than gaining an empty object.
        it "leaves the item without an overrides object" do
          expect(result).to be_success
          expect(result.quote_version.billing_items.dig("plans", 0, "overrides")).to eq(nil)
        end
      end

      # The mirror of the bug this realignment exists for: an override left behind states a currency
      # the deal no longer uses, and blocks approval exactly as a missing one did.
      context "when the item carries an override the new currency makes stale" do
        let(:plan) { create(:plan, organization:, amount_currency: "USD") }
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {"plans" => [plan_item.merge("overrides" => {"amountCurrency" => "EUR"})]}
          )
        end

        # An empty object, not a dropped key: the pages rendering the quote reach for
        # `overrides.name`, and a key that disappeared takes them down.
        it "drops the override and leaves the overrides empty" do
          expect(result).to be_success
          expect(result.quote_version.billing_items.dig("plans", 0, "overrides")).to eq({})
        end

        context "when the item carries other overrides too" do
          let(:quote_version) do
            create(
              :quote_version,
              quote:,
              organization:,
              currency: "EUR",
              billing_items: {
                "plans" => [plan_item.merge("overrides" => {"amountCents" => 50_000, "amountCurrency" => "EUR"})]
              }
            )
          end

          it "drops only the currency override" do
            expect(result).to be_success

            overrides = result.quote_version.billing_items["plans"].sole["overrides"]
            expect(overrides).to eq({"amountCents" => 50_000})
          end
        end

        context "when a coupon carries the stale override" do
          let(:coupon) { create(:coupon, organization:, coupon_type: "fixed_amount", amount_currency: "USD") }
          let(:quote_version) do
            create(
              :quote_version,
              quote:,
              organization:,
              currency: "EUR",
              billing_items: {
                "coupons" => [
                  {
                    "id" => coupon.id,
                    "localId" => "c1",
                    "type" => "coupon",
                    "payload" => {"code" => coupon.code},
                    "overrides" => {"amountCurrency" => "EUR"}
                  }
                ]
              }
            )
          end

          it "drops it too and leaves the overrides empty" do
            expect(result).to be_success
            expect(result.quote_version.billing_items.dig("coupons", 0, "overrides")).to eq({})
          end
        end
      end

      # The figure itself is never converted, so a plan negotiated at 150000 USD becomes 150000 EUR.
      # What must not happen is losing it, which would silently revert the deal to list price.
      context "when the item carries a negotiated price and charge overrides" do
        let(:billable_metric) { create(:billable_metric, organization:) }
        let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "50"}) }
        let(:negotiated) do
          {
            "amountCents" => 150_000,
            "name" => "Enterprise deal",
            "charges" => [
              {"billableMetricCode" => billable_metric.code, "chargeModel" => charge.charge_model, "properties" => {"amount" => "30"}}
            ]
          }
        end
        # The override resolves its charge through the payload snapshot, so the item has to carry one.
        let(:snapshotted) do
          plan_item.merge(
            "payload" => plan_item["payload"].merge(
              "charges" => [
                {"id" => charge.id, "billableMetric" => {"code" => billable_metric.code}, "chargeModel" => charge.charge_model}
              ]
            )
          )
        end
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {"plans" => [snapshotted.merge("overrides" => negotiated)]}
          )
        end

        it "keeps every negotiated value and only restates the currency" do
          expect(result).to be_success

          overrides = result.quote_version.billing_items.dig("plans", 0, "overrides")
          expect(overrides).to eq(negotiated.merge("amountCurrency" => "USD"))
        end
      end

      context "when a coupon carries a negotiated amount" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "fixed_amount", amount_currency: "EUR") }
        let(:quote_version) do
          create(
            :quote_version,
            quote:,
            organization:,
            currency: "EUR",
            billing_items: {
              "coupons" => [
                {
                  "id" => coupon.id,
                  "localId" => "c1",
                  "type" => "coupon",
                  "payload" => {"code" => coupon.code},
                  "overrides" => {"amountCents" => 15_000, "frequency" => "once"}
                }
              ]
            }
          )
        end

        it "keeps it and only restates the currency" do
          expect(result).to be_success

          expect(result.quote_version.billing_items.dig("coupons", 0, "overrides")).to eq(
            {"amountCents" => 15_000, "frequency" => "once", "amountCurrency" => "USD"}
          )
        end
      end

      # The realignment runs before the structural pass, so it must not overwrite a value the
      # validator would have rejected: correcting a stale currency is its job, silently accepting a
      # malformed one is not.
      context "when the submitted value is one the validator would reject" do
        let(:plan) { create(:plan, organization:, amount_currency: "EUR") }
        let(:coupon) { create(:coupon, organization:, coupon_type: "fixed_amount", amount_currency: "EUR") }

        context "with an unknown currency on a plan override" do
          let(:quote_version) do
            create(
              :quote_version,
              quote:,
              organization:,
              currency: "EUR",
              billing_items: {"plans" => [plan_item.merge("overrides" => {"amountCurrency" => "DOUBLOON"})]}
            )
          end

          it "leaves it for the validator" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq({"billing_items.plans.0.overrides.amountCurrency": ["invalid_currency"]})
          end
        end

        context "with an unknown currency on a coupon override" do
          let(:quote_version) do
            create(
              :quote_version,
              quote:,
              organization:,
              currency: "EUR",
              billing_items: {
                "coupons" => [
                  {
                    "id" => coupon.id,
                    "localId" => "c1",
                    "type" => "coupon",
                    "payload" => {"code" => coupon.code},
                    "overrides" => {"amountCurrency" => "DOUBLOON"}
                  }
                ]
              }
            )
          end

          it "leaves it for the validator" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq({"billing_items.coupons.0.overrides.amountCurrency": ["invalid_currency"]})
          end
        end

        context "with an unknown currency on a wallet credit" do
          let(:quote_version) do
            create(
              :quote_version,
              quote:,
              organization:,
              currency: "EUR",
              billing_items: {
                "walletCredits" => [
                  {"localId" => "w1", "type" => "wallet_credit", "payload" => {"currency" => "DOUBLOON", "paidCredits" => "100"}}
                ]
              }
            )
          end

          it "leaves it for the validator" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq({"billing_items.walletCredits.0.payload.currency": ["invalid_currency"]})
          end
        end

        context "with an overrides that is neither an object nor null" do
          let(:quote_version) do
            create(
              :quote_version,
              quote:,
              organization:,
              currency: "EUR",
              billing_items: {"plans" => [plan_item.merge("overrides" => false)]}
            )
          end

          it "leaves it for the validator" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq({"billing_items.plans.0.overrides": ["invalid_type"]})
          end
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

        it "applies the coupon in the new currency" do
          expect(result).to be_success
          expect(result.quote_version.billing_items.dig("coupons", 0, "overrides", "amountCurrency")).to eq("USD")
        end
      end

      context "when a percentage coupon is quoted" do
        let(:coupon) { create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10, amount_currency: nil) }
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

        # A percentage coupon carries no currency, so there is nothing to realign.
        it "leaves it without an overrides object" do
          expect(result).to be_success
          expect(result.quote_version.billing_items.dig("coupons", 0, "overrides")).to eq(nil)
        end
      end

      # A draft may legitimately have no currency yet, and realigning against one would stamp an
      # explicit null across every item the catalog does not match.
      context "when the deal currency is cleared" do
        let(:update_params) { {currency: nil} }

        it "leaves the billing items as submitted" do
          expect(result).to be_success
          expect(result.quote_version.billing_items).to eq({"plans" => [plan_item]})
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

    # The realignment is what keeps the stored copies coherent, and the payload is rewritten wholesale
    # by whoever saves it, so a copy the deal no longer matches can arrive on an update that leaves
    # the currency alone.
    context "when a saved payload carries a currency the deal no longer matches", :premium do
      let(:plan) { create(:plan, organization:, amount_currency: "EUR") }
      let(:coupon) { create(:coupon, organization:, coupon_type: "fixed_amount", amount_currency: "EUR") }
      let(:quote_version) { create(:quote_version, quote:, organization:, currency: "USD") }
      let(:update_params) do
        {
          billing_items: {
            "plans" => [
              {
                "id" => plan.id,
                "localId" => "p1",
                "type" => "plan",
                "payload" => {"code" => plan.code, "startDate" => Date.current.iso8601}
              }
            ],
            "coupons" => [
              {"id" => coupon.id, "localId" => "c1", "type" => "coupon", "payload" => {"code" => coupon.code}}
            ],
            "walletCredits" => [
              {"localId" => "w1", "type" => "wallet_credit", "payload" => {"currency" => "EUR", "paidCredits" => "100"}}
            ]
          }
        }
      end

      it "repairs every copy rather than rejecting the save" do
        expect(result).to be_success

        items = result.quote_version.billing_items
        expect(items.dig("plans", 0, "overrides", "amountCurrency")).to eq("USD")
        expect(items.dig("coupons", 0, "overrides", "amountCurrency")).to eq("USD")
        expect(items.dig("walletCredits", 0, "payload", "currency")).to eq("USD")
      end
    end

    # The realignment runs before the structural pass, so a malformed payload reaches it first. It
    # must leave anything unexpected alone and let the validator report it, never raise.
    context "when the submitted billing items are malformed", :premium do
      let(:update_params) { {billing_items:} }

      [
        {"plans" => ["bad"]},
        {"plans" => [1]},
        {"plans" => {"id" => "not-an-array"}},
        {"plans" => [{"overrides" => "nope"}]},
        {"coupons" => [["pair"]]},
        {"walletCredits" => ["bad"]}
      ].each do |malformed|
        context "with #{malformed.to_json}" do
          let(:billing_items) { malformed }

          it "returns a validation failure rather than raising" do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
          end
        end
      end

      # Reported on the collection rather than on an item, which is only true if the payload reached
      # the validator in the shape it was sent rather than coerced into pairs on the way.
      context "with a collection that is not an array" do
        let(:billing_items) { {"plans" => {"id" => "not-an-array"}} }

        it "leaves the shape untouched for the validator" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq({"billing_items.plans": ["invalid_type"]})
        end
      end

      # A malformed overrides is only reached once the item resolves to a catalog record.
      context "with an overrides that is not an object on a known plan" do
        let(:plan) { create(:plan, organization:, amount_currency: "EUR") }
        let(:billing_items) do
          {"plans" => [{"id" => plan.id, "localId" => "p1", "type" => "plan", "overrides" => "nope"}]}
        end

        it "returns a validation failure rather than raising" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
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
